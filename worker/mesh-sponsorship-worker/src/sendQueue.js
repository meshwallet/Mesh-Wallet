import {
  createTronWeb,
  normalizePrivateKey,
  recipientHasUSDT,
  ensureAccountActivated,
  isAccountActivated,
  waitForAccountActivated,
  briefWaitForTx,
  broadcastSignedTransaction,
  getUSDTBalance,
  probeAccountEnergy,
  ensureSenderBandwidth,
  ensureSenderBandwidthOnce,
  ACTIVATION_TRX_SUN,
  verifyRouterSendFee,
} from "./tron.js";
import { ensureEnergyForSender } from "./energyProvider.js";
import {
  obligationKey,
  trySettleObligationFee,
  putFeeObligation,
  KvWriteLimitError,
  canProcessEphemeral,
  recoverMissedRouterFeeFromOps,
  isFeeWaived,
} from "./feeObligations.js";

const USDT_TRANSFER_SELECTOR = "a9059cbb";
const USDT_APPROVE_SELECTOR = "095ea7b3";
const SEND_WITH_FEE_SELECTOR = "67156f76";
const HANDOFF_RETRY_GRACE_MS = 5 * 60 * 1000;
const STALE_PROCESSING_MS = 60_000;
const MAX_QUEUE_ATTEMPTS = 16;
const DIRECT_SEND_FAST_WALL_MS = 28_000;
const DIRECT_SEND_FAST_MAX_ATTEMPTS = 3;
const DIRECT_SEND_MAX_WALL_MS = 55_000;
const DIRECT_SEND_INVOCATION_WALL_MS = 55_000;
const EPHEMERAL_STATUS_PREFIX = "eph:";
const activeDirectRouterSends = new Set();

async function tryAcquireDirectSendLock(env, id) {
  if (activeDirectRouterSends.has(id)) {
    return false;
  }
  activeDirectRouterSends.add(id);

  if (env.FEE_OBLIGATIONS) {
    const key = `direct-send:${id}`;
    try {
      const existing = await env.FEE_OBLIGATIONS.get(key);
      if (existing) {
        activeDirectRouterSends.delete(id);
        return false;
      }
      await env.FEE_OBLIGATIONS.put(key, String(Date.now()), { expirationTtl: 600 });
    } catch (error) {
      if (!(error instanceof KvWriteLimitError)) {
        console.warn("direct send lock KV failed", id, error);
      }
    }
  }
  return true;
}

async function releaseDirectSendLock(env, id) {
  activeDirectRouterSends.delete(id);
  if (!env.FEE_OBLIGATIONS) return;
  try {
    await env.FEE_OBLIGATIONS.delete(`direct-send:${id}`);
  } catch (error) {
    if (!(error instanceof KvWriteLimitError)) {
      console.warn("direct send unlock KV failed", id, error);
    }
  }
}
/** Relay wallets are brand-new; Tron activation can take 30–90s across retries. */
const ACTIVATION_MAX_CHECKS = 15;
const ACTIVATION_INTERVAL_MS = 3_500;
const ACTIVATION_POST_TX_WAIT_MS = 8_000;

/** Batches in-memory obligation updates; flushes only at checkpoints to save KV writes. */
class ObligationWriter {
  constructor(env, obligation, { ephemeral = false } = {}) {
    this.env = env;
    this.obligation = obligation;
    this.ephemeral = ephemeral;
    this.dirty = false;
  }

  touch() {
    this.obligation.updatedAtMs = Date.now();
    this.dirty = true;
  }

  async flush() {
    if (!this.dirty) return;
    if (this.ephemeral) {
      this.dirty = false;
      return;
    }
    try {
      await putFeeObligation(this.env, this.obligation.id, this.obligation);
      this.dirty = false;
    } catch (error) {
      if (error instanceof KvWriteLimitError && canProcessEphemeral(this.obligation)) {
        console.warn("KV write limit — continuing send in memory", this.obligation.id);
        this.ephemeral = true;
        this.dirty = false;
        return;
      }
      throw error;
    }
  }
}

function queueResult(needsContinue, obligation, extra = {}) {
  return { needsContinue, obligation, ...extra };
}

export async function getSendObligationStatus(env, obligationId) {
  if (!env.FEE_OBLIGATIONS) {
    return { ok: false, message: "FEE_OBLIGATIONS KV not configured" };
  }
  const raw = await env.FEE_OBLIGATIONS.get(obligationKey(obligationId));
  let obligation = null;
  if (raw) {
    try {
      obligation = JSON.parse(raw);
    } catch {
      obligation = null;
    }
  }

  if (!obligation) {
    const ephemeralRaw = await env.FEE_OBLIGATIONS.get(
      `${EPHEMERAL_STATUS_PREFIX}${obligationId}`
    );
    if (!ephemeralRaw) {
    return { ok: false, message: "Send not found" };
  }
    try {
      const ephemeral = JSON.parse(ephemeralRaw);
      return {
        ok: true,
        id: obligationId,
        status: ephemeral.status ?? "processing_queue",
        mainTxID: ephemeral.mainTxID ?? null,
        feeTxID: ephemeral.feeTxID ?? null,
        lastError: ephemeral.lastError ?? null,
        currentStepIndex: ephemeral.currentStepIndex ?? 0,
        totalSteps: ephemeral.totalSteps ?? 1,
        lastStepLabel: ephemeral.lastStepLabel ?? null,
        lastStepTxID: ephemeral.lastStepTxID ?? null,
        networkStartedAtMs: ephemeral.networkStartedAtMs ?? null,
        updatedAtMs: ephemeral.updatedAtMs ?? null,
        queueAttempts: ephemeral.queueAttempts ?? 0,
        isPrivateSend: ephemeral.isPrivateSend === true,
        feeCollectedVia: ephemeral.feeCollectedVia ?? null,
        hasSignedMain: ephemeral.hasSignedMain !== false,
      };
    } catch {
      return { ok: false, message: "Send not found" };
    }
  }

  const steps = resolveSignedSteps(obligation);
  return {
    ok: true,
    id: obligation.id,
    status: obligation.status,
    mainTxID: obligation.mainTxID ?? null,
    feeTxID: obligation.feeTxID ?? null,
    lastError: obligation.lastError ?? null,
    currentStepIndex: obligation.currentStepIndex ?? 0,
    totalSteps: steps.length,
    lastStepLabel: obligation.lastStepLabel ?? null,
    lastStepTxID: obligation.lastStepTxID ?? null,
    networkStartedAtMs: obligation.networkStartedAtMs ?? null,
    updatedAtMs: obligation.updatedAtMs ?? null,
    queueAttempts: obligation.queueAttempts ?? 0,
    isPrivateSend: obligation.isPrivateSend === true,
    hasSignedMain: Boolean(
      obligation.signedMainTxJSON ||
        (Array.isArray(obligation.signedMainTxSteps) &&
          obligation.signedMainTxSteps.length > 0)
    ),
  };
}

/**
 * Processes one queue step per worker invocation (private routes need multiple hops).
 * Returns { needsContinue: true, obligation } when more hops remain.
 */
export async function processQueuedSend(env, obligationId, options = {}) {
  if (!env.MESH_OPS_TRON_PRIVATE_KEY || !env.FEE_OBLIGATIONS) {
    return queueResult(false);
  }

  let obligation = options.obligation ?? null;
  let ephemeral = options.ephemeral === true;

  if (!obligation) {
    const raw = await env.FEE_OBLIGATIONS.get(obligationKey(obligationId));
    if (!raw) return queueResult(false);
    obligation = JSON.parse(raw);
  } else if (!ephemeral && env.FEE_OBLIGATIONS) {
    const raw = await env.FEE_OBLIGATIONS.get(obligationKey(obligationId));
    ephemeral = !raw;
  }

  if (
    obligation.status !== "queued" &&
    obligation.status !== "processing_queue" &&
    obligation.status !== "failed"
  ) {
    return queueResult(false, obligation);
  }

  const now = Date.now();

  if (!ephemeral) {
  // Legacy sends stuck in processing_queue before any ops spend.
  if (
    obligation.status === "processing_queue" &&
    !obligation.networkStartedAtMs
  ) {
    const age = now - Number(obligation.updatedAtMs || 0);
    if (age >= STALE_PROCESSING_MS) {
      obligation.status = "queued";
      obligation.queueLockAtMs = null;
    }
  }

  const lockAt = Number(obligation.queueLockAtMs || 0);
  const lockAge = lockAt > 0 ? now - lockAt : STALE_PROCESSING_MS;
  if (lockAge < STALE_PROCESSING_MS && obligation.status !== "failed") {
      return queueResult(false, obligation);
    }
  }

  if (obligation.status === "failed") {
    obligation.status = "queued";
    obligation.lastError = null;
  }

  obligation.queueLockAtMs = now;
  const writer = new ObligationWriter(env, obligation, { ephemeral });
  if (!ephemeral) {
    writer.touch();
    await writer.flush();
    ephemeral = writer.ephemeral;
  }

  const privateKey = normalizePrivateKey(env.MESH_OPS_TRON_PRIVATE_KEY);
  const tronWeb = createTronWeb(privateKey, env);
  const usdtContract = env.USDT_CONTRACT || "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t";

  try {
    const steps = resolveSignedSteps(obligation);
    if (steps.length === 0) {
      throw new Error("Queued send missing signed transactions");
    }

    obligation = await advancePastCompletedRouterApprove(
      tronWeb,
      obligation,
      steps,
      env,
      usdtContract
    );

    const startIndex = Number(obligation.currentStepIndex || 0);
    if (startIndex >= steps.length) {
      return await finalizeQueuedSend(env, writer);
    }

    const index = startIndex;
    const step = steps[index];
    if (obligation.sendMode === "direct_router") {
      if (step.label === "router_approve") {
        validateSignedRouterApproveStep(tronWeb, step, obligation, env, usdtContract);
      } else {
        validateSignedRouterStep(tronWeb, step, obligation, env);
      }
    } else {
    validateSignedUSDTStep(tronWeb, step, usdtContract);
    }

    // Private multi-hop: wait for USDT on relay wallet before the next hop.
    if (index > 0 && obligation.isPrivateSend === true) {
      await waitForUSDTBalance(tronWeb, step.fromAddress, step.amountUSDT, usdtContract, {
        timeoutMs: steps.length > 2 ? 150_000 : 120_000,
      });
    }

    obligation.currentStepIndex = index;
    obligation.lastStepLabel = step.label ?? `step_${index + 1}`;
    writer.touch();
    await writer.flush();

    const coldStart = await isObligationColdStart(env, obligation);
    if (coldStart) {
      const activationTx = await ensureStepActivation(
        tronWeb,
        step.fromAddress,
        writer,
        env
      );
      if (activationTx) {
        markNetworkStarted(writer);
        await briefWaitForTx(tronWeb, activationTx, ACTIVATION_POST_TX_WAIT_MS);
      }
      const recipientActivation = shouldActivateStepDestination(step, env, obligation)
        ? await ensureStepActivation(tronWeb, step.toAddress, writer, env)
        : null;
      if (recipientActivation) {
        markNetworkStarted(writer);
        await briefWaitForTx(tronWeb, recipientActivation, ACTIVATION_POST_TX_WAIT_MS);
      }
    }

    const hasUsdt = await recipientHasUSDT(tronWeb, step.toAddress, usdtContract);
    const energyMinimum = step.highEnergy === true ? 55_000 : 28_000;
    const rent = await ensureStepEnergy(tronWeb, step, index, writer, env, {
      hasUsdt,
      energyMinimum,
    });
    if (rent.delegationTx || rent.paymentTx || rent.trxPaid > 0) {
      markNetworkStarted(writer);
    }
    await writer.flush();

    if (isFeeWaivedDirectSend(obligation)) {
      const bandwidthTx = await ensureSenderBandwidthOnce(tronWeb, step.fromAddress, env);
      if (bandwidthTx) {
        markNetworkStarted(writer);
        await writer.flush();
      }
    }

    const stepTxID = await broadcastSignedTransaction(tronWeb, env, step.signedTxJSON);
    await briefWaitForTx(tronWeb, stepTxID, 20_000);

    if (step.label === "router_approve") {
      const router =
        env.MESH_SEND_ROUTER_ADDRESS?.trim() ||
        obligation.routerAddress?.trim();
      if (!router) {
        throw new Error("MESH_SEND_ROUTER_ADDRESS not configured");
      }
      const required =
        Number(obligation.amountUSDT || 0) + Number(obligation.feeUSDT || 0);
      await waitForRouterAllowance(
        tronWeb,
        step.fromAddress,
        router,
        usdtContract,
        required,
        { timeoutMs: 60_000 }
      );
    }

    obligation.currentStepIndex = index + 1;
    obligation.lastStepTxID = stepTxID;
    writer.touch();

    if (index < steps.length - 1) {
      obligation.status = "queued";
      obligation.queueLockAtMs = null;
      await writer.flush();
      return queueResult(true, writer.obligation);
    }

    obligation.mainTxID = stepTxID;
    await writer.flush();
    return await finalizeQueuedSend(env, writer);
  } catch (error) {
    console.error("processQueuedSend failed", obligationId, error);
    const message = error?.message || String(error);
    const attempts = Number(obligation.queueAttempts || 0) + 1;
    const coldStart = await isObligationColdStart(env, writer.obligation);
    if (shouldRetryQueuedSend(writer.obligation, message, { coldStart })) {
      obligation.status = "queued";
      obligation.lastError = message;
      obligation.queueAttempts = attempts;
      obligation.queueLockAtMs = null;
      writer.touch();
      await writer.flush();
      return queueResult(true, writer.obligation);
    }

    const expired = String(message || "").toLowerCase().includes("expired");
    obligation.status = expired ? "expired_needs_resign" : "failed";
    obligation.lastError = expired ? "EXPIRED_NEEDS_RESIGN" : message;
    obligation.queueAttempts = attempts;
    obligation.queueLockAtMs = null;
    writer.touch();
    await writer.flush();
    return queueResult(false, writer.obligation);
  }
}

/** Never send a second 1 TRX activation for the same address on retry. */
async function ensureStepActivation(tronWeb, address, writer, env) {
  const obligation = writer.obligation;
  if (await isAccountActivated(tronWeb, address)) {
    const hadPending = Boolean(obligation.pendingActivations?.[address]);
    clearPendingActivation(obligation, address);
    if (hadPending) {
      writer.touch();
      await writer.flush();
    }
    return null;
  }

  let activationTx = obligation.pendingActivations?.[address] ?? null;
  if (!activationTx) {
    const payment = await tronWeb.trx.sendTransaction(address, ACTIVATION_TRX_SUN);
    activationTx = payment?.txid ?? payment?.transaction?.txID ?? payment?.txID;
    if (!activationTx) {
      throw new Error(`Failed to activate Tron address ${address}`);
    }
    if (!obligation.pendingActivations) obligation.pendingActivations = {};
    obligation.pendingActivations[address] = activationTx;
    writer.touch();
    await writer.flush();
    await briefWaitForTx(tronWeb, activationTx, 6_000);
  }

  if (
    await waitForAccountActivated(
      tronWeb,
      address,
      ACTIVATION_MAX_CHECKS,
      ACTIVATION_INTERVAL_MS
    )
  ) {
    clearPendingActivation(obligation, address);
    writer.touch();
    await writer.flush();
    return activationTx;
  }

  throw new Error(`Tron address ${address} did not activate in time`);
}

function clearPendingActivation(obligation, address) {
  if (!obligation.pendingActivations?.[address]) return;
  delete obligation.pendingActivations[address];
  if (Object.keys(obligation.pendingActivations).length === 0) {
    delete obligation.pendingActivations;
  }
}

/** Never pay TronNRG twice for the same queue step while energy is still arriving. */
async function ensureStepEnergy(
  tronWeb,
  step,
  index,
  writer,
  env,
  { hasUsdt, energyMinimum, energyWaitTimeoutMs }
) {
  const energyWaitMs =
    energyWaitTimeoutMs ?? (step.highEnergy === true ? 180_000 : 90_000);
  const obligation = writer.obligation;
  const currentEnergy = await probeAccountEnergy(tronWeb, step.fromAddress);
  if (currentEnergy >= energyMinimum) {
    return {
      skipped: true,
      trxPaid: 0,
      delegationTx: null,
      paymentTx: null,
    };
  }

  const stepKey = String(index);
  const prior = obligation.energyPayments?.[stepKey];
  const alreadyPaid =
    prior?.delegateTo === step.fromAddress &&
    prior?.paymentTx &&
    Date.now() - Number(prior.atMs || 0) < 30 * 60 * 1000;

  if (alreadyPaid) {
    await waitForSenderEnergy(tronWeb, step.fromAddress, energyMinimum, {
      timeoutMs: energyWaitMs,
    });
    return {
      skipped: true,
      trxPaid: 0,
      delegationTx: prior.delegationTx ?? null,
      paymentTx: prior.paymentTx,
    };
  }

  const rent = await ensureEnergyForSender({
    tronWeb,
    delegateTo: step.fromAddress,
    highEnergy: step.highEnergy === true,
    hasUsdtOnRecipient: hasUsdt,
    env,
    minimumEnergy: energyMinimum,
  });

  if (rent.paymentTx || rent.trxPaid > 0) {
    if (!obligation.energyPayments) obligation.energyPayments = {};
    obligation.energyPayments[stepKey] = {
      delegateTo: step.fromAddress,
      paymentTx: rent.paymentTx ?? null,
      delegationTx: rent.delegationTx ?? null,
      trxPaid: rent.trxPaid ?? 0,
      atMs: Date.now(),
    };
    writer.touch();
    await writer.flush();
  }

  if (rent.delegationTx) {
    await briefWaitForTx(tronWeb, rent.delegationTx, step.highEnergy ? 15_000 : 8_000);
  }

  await waitForSenderEnergy(tronWeb, step.fromAddress, energyMinimum, {
    timeoutMs: energyWaitMs,
  });

  return rent;
}

function markNetworkStarted(writer) {
  const obligation = writer.obligation;
  if (obligation.networkStartedAtMs) return;
  obligation.networkStartedAtMs = Date.now();
  obligation.status = "processing_queue";
  writer.touch();
}

async function finalizeQueuedSend(env, writerOrObligation) {
  const obligation = writerOrObligation.obligation ?? writerOrObligation;
  const writer =
    writerOrObligation.obligation != null
      ? writerOrObligation
      : new ObligationWriter(env, obligation);

  if (obligation.sendMode === "direct_router") {
    obligation.status = "settled";
    obligation.feeCollectedVia = "router";
    obligation.feeTxID = obligation.mainTxID ?? obligation.feeTxID ?? "included";
    writer.touch();
    await writer.flush();
    return queueResult(false, writer.obligation);
  }

  if (isFeeWaived(obligation)) {
    obligation.status = "settled";
    obligation.feeCollectedVia = "waived";
    obligation.feeTxID = obligation.feeTxID ?? "waived";
    writer.touch();
    await writer.flush();
    return queueResult(false, writer.obligation);
  }

  obligation.status = "send_confirmed_fee_pending";
  writer.touch();
  await writer.flush();

  if (writer.ephemeral) {
    return queueResult(false, writer.obligation);
  }

  for (let attempt = 0; attempt < 5; attempt++) {
    if (attempt > 0) {
      await sleep(4_000 * attempt);
    }

    const raw = await env.FEE_OBLIGATIONS.get(obligationKey(obligation.id));
    if (!raw) break;

    const latest = JSON.parse(raw);
    if (latest.feeTxID) break;

    const result = await trySettleObligationFee(env, latest);
    if (result.settled === true) break;
  }

  return queueResult(false, writer.obligation);
}

function workerOrigin(env, requestOrigin) {
  const configured = env.WORKER_PUBLIC_URL?.trim();
  if (configured) return configured.replace(/\/$/, "");
  if (requestOrigin) return requestOrigin.replace(/\/$/, "");
  return "https://mesh-sponsorship-relay.meshwallet.workers.dev";
}

export async function triggerContinueQueuedSend(env, obligationId, requestOrigin) {
  await postContinueQueuedSend(env, { id: obligationId }, requestOrigin);
}

/** Chains ephemeral hops via HTTP so each step gets a fresh worker invocation. */
export async function triggerContinueEphemeralSend(env, obligation, requestOrigin) {
  await postContinueQueuedSend(
    env,
    { id: obligation.id, ephemeral: true, obligation },
    requestOrigin
  );
}

async function postContinueQueuedSend(env, body, requestOrigin) {
  const origin = workerOrigin(env, requestOrigin);
  const secret = env.RELAY_AUTH_SECRET ?? env.MESH_RELAY_AUTH_SECRET;
  if (!secret) {
    console.warn("continue-queued-send skipped: no relay auth secret");
    return;
  }

  try {
    const response = await fetch(`${origin}/v1/continue-queued-send`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${secret}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
    });
    if (!response.ok) {
      const detail = await response.text();
      console.error("continue-queued-send HTTP", response.status, detail);
    }
  } catch (error) {
    console.error("continue-queued-send fetch failed", body?.id, error);
  }
}

const ephemeralStatusLastWrite = new Map();

async function touchEphemeralSendStatus(env, id, fields, { force = false } = {}) {
  if (!env.FEE_OBLIGATIONS || !id) return;
  const terminal =
    fields.status === "settled" ||
    fields.status === "failed" ||
    Boolean(fields.mainTxID);
  const now = Date.now();
  const lastWrite = ephemeralStatusLastWrite.get(id) || 0;
  if (!force && !terminal && now - lastWrite < 30_000) {
    return;
  }
  ephemeralStatusLastWrite.set(id, now);

  const key = `${EPHEMERAL_STATUS_PREFIX}${id}`;
  try {
    let prior = {};
    const raw = await env.FEE_OBLIGATIONS.get(key);
    if (raw) {
      try {
        prior = JSON.parse(raw);
      } catch {
        prior = {};
      }
    }
    const next = { ...prior, ...fields, id, updatedAtMs: now };
    await env.FEE_OBLIGATIONS.put(key, JSON.stringify(next), { expirationTtl: 86_400 });
  } catch (error) {
    if (!(error instanceof KvWriteLimitError)) {
      console.warn("ephemeral status write failed", id, error);
    }
  }
}

/** Register waitUntil: approve + send in one run, retry transient failures. */
export async function runDirectRouterSendUntilDone(env, obligation, options = {}) {
  let current = { ...obligation, status: "processing_queue" };
  const steps = resolveSignedSteps(current);
  await touchEphemeralSendStatus(env, current.id, {
    status: "processing_queue",
    sendMode: current.sendMode ?? "direct_router",
    isPrivateSend: false,
    totalSteps: steps.length,
    hasSignedMain: steps.length > 0,
  });

  const maxAttempts = 3;
  let lastError = null;

  for (let attempt = 0; attempt < maxAttempts; attempt += 1) {
    try {
      const result = await processDirectRouterSend(env, current, options);
      current = result?.obligation ?? current;
      await touchEphemeralSendStatus(env, current.id, {
        status: current.status ?? "processing_queue",
        mainTxID: current.mainTxID ?? null,
        feeTxID: current.feeTxID ?? null,
        lastError: current.lastError ?? null,
        currentStepIndex: current.currentStepIndex ?? 0,
        totalSteps: steps.length,
        lastStepLabel: current.lastStepLabel ?? null,
        lastStepTxID: current.lastStepTxID ?? null,
        networkStartedAtMs: current.networkStartedAtMs ?? null,
        feeCollectedVia: current.feeCollectedVia ?? null,
        hasSignedMain: true,
      });
      if (current.mainTxID || current.status === "settled") {
        return current;
      }
      if (attempt + 1 < maxAttempts) {
        await sleep(2_000 + attempt * 1_500);
        continue;
      }
      throw new Error(current.lastError || "Direct router send incomplete");
    } catch (error) {
      lastError = error;
      if (error?.obligationSnapshot) {
        current = { ...current, ...error.obligationSnapshot };
      }
      const message = error?.message || String(error);
      console.error("direct router attempt failed", current.id, attempt, message);
      await touchEphemeralSendStatus(env, current.id, {
        status: "failed",
        lastError: message,
        currentStepIndex: current.currentStepIndex ?? 0,
        lastStepLabel: current.lastStepLabel ?? null,
        lastStepTxID: current.lastStepTxID ?? null,
        networkStartedAtMs: current.networkStartedAtMs ?? null,
        hasSignedMain: true,
      });
      if (!isRetryableQueueError(message) || attempt + 1 >= maxAttempts) {
        throw error;
      }
      if (message.includes("already running")) {
        await sleep(3_000);
      }
      current = { ...current, status: "queued", lastError: message };
      await sleep(2_000 + attempt * 1_500);
    }
  }

  throw lastError || new Error("Direct router send incomplete");
}

/** Direct router: energy + bandwidth once; approve + send in one worker run. */
export async function processDirectRouterSend(env, obligation, options = {}) {
  if (!env.MESH_OPS_TRON_PRIVATE_KEY) {
    throw new Error("MESH_OPS_TRON_PRIVATE_KEY not configured");
  }

  const sendId = obligation?.id?.trim();
  if (!sendId) {
    throw new Error("Direct router send missing obligation id");
  }

  if (!(await tryAcquireDirectSendLock(env, sendId))) {
    throw new Error("Direct router send already running");
  }

  const wallStartedAt = Date.now();
  const timeLeftMs = () => DIRECT_SEND_MAX_WALL_MS - (Date.now() - wallStartedAt);
  const requestOrigin = options.requestOrigin ?? null;

  let current = { ...obligation, status: "processing_queue" };

  try {
    const privateKey = normalizePrivateKey(env.MESH_OPS_TRON_PRIVATE_KEY);
    const tronWeb = createTronWeb(privateKey, env);
    const usdtContract = env.USDT_CONTRACT || "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t";
    const router = env.MESH_SEND_ROUTER_ADDRESS?.trim();
    if (!router) {
      throw new Error("MESH_SEND_ROUTER_ADDRESS not configured");
    }

    let steps = resolveSignedSteps(current);
    if (steps.length === 0) {
      throw new Error("Queued send missing signed transactions");
    }

    current = await advancePastCompletedRouterApprove(
      tronWeb,
      current,
      steps,
      env,
      usdtContract
    );
    steps = resolveSignedSteps(current);

    const sender = steps[0]?.fromAddress;
    if (!sender) {
      throw new Error("Direct router send missing sender address");
    }

    const startIndex = Number(current.currentStepIndex || 0);
    const writer = new ObligationWriter(env, current, { ephemeral: true });

    const required =
      Number(current.amountUSDT || 0) + Number(current.feeUSDT || 0);

    for (let index = startIndex; index < steps.length; index += 1) {
      const step = steps[index];
      if (step.label === "router_approve") {
        validateSignedRouterApproveStep(tronWeb, step, current, env, usdtContract);
      } else {
        validateSignedRouterStep(tronWeb, step, current, env);
      }

      const energyMinimum = directRouterEnergyMinimum(steps, index);
      await ensureDirectRouterSenderReady(tronWeb, sender, writer, env, {
        maxWaitMs: Math.max(8_000, Math.min(16_000, timeLeftMs() - 5_000)),
        minimumEnergy: energyMinimum,
        highEnergy: energyMinimum >= 55_000,
        allowSupplementalRent: step.label !== "router_approve",
      });
      current = writer.obligation;

      if (!current.bandwidthTopupAtMs) {
        const bandwidthTx = await ensureSenderBandwidthOnce(tronWeb, sender, env);
        if (bandwidthTx) {
          current.bandwidthTopupAtMs = Date.now();
          current.bandwidthTopupTx = bandwidthTx;
        }
      }

      current.currentStepIndex = index;
      current.lastStepLabel = step.label ?? `step_${index + 1}`;
      current.networkStartedAtMs = current.networkStartedAtMs ?? Date.now();

      let stepTxID;
      try {
        stepTxID = await broadcastSignedTransaction(tronWeb, env, step.signedTxJSON);
      } catch (error) {
        console.error(
          "direct router broadcast failed",
          sendId,
          step.label ?? index,
          error?.message || error
        );
        throw error;
      }

      console.log("direct router broadcast ok", sendId, step.label ?? index, stepTxID);
      await briefWaitForTx(
        tronWeb,
        stepTxID,
        Math.max(4_000, Math.min(12_000, timeLeftMs() - 2_000))
      );

      if (step.label === "router_approve") {
        await waitForRouterAllowance(
          tronWeb,
          step.fromAddress,
          router,
          usdtContract,
          required,
          { timeoutMs: Math.max(6_000, Math.min(15_000, timeLeftMs() - 2_000)) }
        );
        current.lastStepTxID = stepTxID;
        current.currentStepIndex = index + 1;
        continue;
      }

      current.mainTxID = stepTxID;
      current.lastStepTxID = stepTxID;
      current.status = "settled";
      current.feeCollectedVia = "router";
      current.feeTxID = stepTxID;

      const expectedFee = Number(current.feeUSDT || 0);
      if (expectedFee > 0) {
        const feeVerified = await verifyRouterSendFee(
          tronWeb,
          stepTxID,
          env,
          expectedFee
        );
        if (!feeVerified) {
          console.error("router send missing treasury fee", sendId, stepTxID);
          try {
            const recoveryTxID = await recoverMissedRouterFeeFromOps(
              env,
              sender,
              expectedFee
            );
            current.feeTxID = recoveryTxID;
            current.feeCollectedVia = "ops_recovery";
          } catch (recoveryError) {
            console.error("router fee recovery failed", sendId, recoveryError);
            current.status = "send_confirmed_fee_pending";
            current.feeCollectedVia = null;
            current.feeTxID = null;
            current.lastError = "Main send confirmed but treasury fee missing";
          }
        }
      }

      console.log("direct router send settled", sendId, stepTxID, current.feeCollectedVia);
      return queueResult(false, current);
    }

    throw new Error("Direct router send finished without broadcasting USDT");
  } catch (error) {
    error.obligationSnapshot = current;
    throw error;
  } finally {
    await releaseDirectSendLock(env, sendId);
  }
}

/** Plain USDT transfer: ops pays energy + bandwidth, no on-chain fee. */
export async function processSimpleDirectSend(env, obligation, options = {}) {
  if (!env.MESH_OPS_TRON_PRIVATE_KEY) {
    throw new Error("MESH_OPS_TRON_PRIVATE_KEY not configured");
  }

  const sendId = obligation?.id?.trim();
  if (!sendId) {
    throw new Error("Direct send missing obligation id");
  }

  if (!(await tryAcquireDirectSendLock(env, sendId))) {
    throw new Error("Direct send already running");
  }

  const fastPath = options.fastPath === true;
  const wallMs = fastPath ? DIRECT_SEND_FAST_WALL_MS : DIRECT_SEND_MAX_WALL_MS;
  const wallStartedAt = Date.now();
  const timeLeftMs = () => wallMs - (Date.now() - wallStartedAt);
  let current = { ...obligation, status: "processing_queue" };
  let writer = null;

  try {
    const privateKey = normalizePrivateKey(env.MESH_OPS_TRON_PRIVATE_KEY);
    const tronWeb = createTronWeb(privateKey, env);
    const usdtContract = env.USDT_CONTRACT || "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t";

    const steps = resolveSignedSteps(current);
    if (steps.length === 0) {
      throw new Error("Queued send missing signed transactions");
    }

    const step = steps[0];
    validateSignedUSDTStep(tronWeb, step, usdtContract);

    const sender = step.fromAddress;
    if (!sender) {
      throw new Error("Direct send missing sender address");
    }

    const loaded = await obligationWriterForSend(env, current);
    writer = loaded.writer;
    const ephemeral = loaded.ephemeral;
    current = loaded.obligation;
    const energyMinimum = current.highEnergy === true ? 55_000 : 28_000;

    const coldStart =
      options.coldStart === true ||
      (options.coldStart !== false &&
        (await isObligationColdStart(env, current)));
    if (coldStart) {
      const activationTx = await ensureStepActivation(tronWeb, sender, writer, env);
      if (activationTx) {
        current.networkStartedAtMs = current.networkStartedAtMs ?? Date.now();
        await briefWaitForTx(
          tronWeb,
          activationTx,
          Math.max(4_000, Math.min(ACTIVATION_POST_TX_WAIT_MS, timeLeftMs() - 4_000))
        );
      }
      current = writer.obligation;
    }

    const energyWaitTimeoutMs = fastPath
      ? Math.max(6_000, Math.min(16_000, timeLeftMs() - 6_000))
      : Math.max(10_000, Math.min(28_000, timeLeftMs() - 6_000));

    if (current.sendMode === "direct_router") {
      await ensureDirectRouterSenderReady(tronWeb, sender, writer, env, {
        maxWaitMs: energyWaitTimeoutMs,
        minimumEnergy: energyMinimum,
        highEnergy: energyMinimum >= 55_000,
        allowSupplementalRent: true,
      });
    } else {
      const hasUsdt = await recipientHasUSDT(tronWeb, step.toAddress, usdtContract);
      const rent = await ensureStepEnergy(tronWeb, step, 0, writer, env, {
        hasUsdt,
        energyMinimum,
        energyWaitTimeoutMs,
      });
      if (rent.delegationTx || rent.paymentTx || (rent.trxPaid ?? 0) > 0) {
        current.networkStartedAtMs = current.networkStartedAtMs ?? Date.now();
      }
    }
    current = writer.obligation;

    if (!current.bandwidthTopupAtMs) {
      const bandwidthTx = await ensureSenderBandwidthOnce(tronWeb, sender, env);
      if (bandwidthTx) {
        current.bandwidthTopupAtMs = Date.now();
        current.bandwidthTopupTx = bandwidthTx;
      }
    }

    current.currentStepIndex = 0;
    current.lastStepLabel = step.label ?? "direct";
    current.networkStartedAtMs = current.networkStartedAtMs ?? Date.now();

    const stepTxID = await broadcastSignedTransaction(tronWeb, env, step.signedTxJSON);
    console.log("simple direct broadcast ok", sendId, stepTxID);
    await briefWaitForTx(
      tronWeb,
      stepTxID,
      Math.max(4_000, Math.min(12_000, timeLeftMs() - 2_000))
    );

    current.mainTxID = stepTxID;
    current.lastStepTxID = stepTxID;
    current.status = "settled";
    current.feeCollectedVia = "waived";
    current.feeTxID = "waived";
    console.log("simple direct send settled", sendId, stepTxID);
    const settledWriter = new ObligationWriter(env, current, { ephemeral });
    settledWriter.touch();
    await settledWriter.flush();
    return queueResult(false, settledWriter.obligation);
  } catch (error) {
    if (writer) {
      current = writer.obligation;
      writer.touch();
      try {
        await writer.flush();
      } catch (flushError) {
        console.error("simple direct flush failed", sendId, flushError);
      }
    }
    error.obligationSnapshot = current;
    throw error;
  } finally {
    await releaseDirectSendLock(env, sendId);
  }
}

/** Fast path for activated wallets — original 3-attempt direct send. */
async function runSimpleSendFast(env, obligation, options = {}) {
  let current = { ...obligation, status: "processing_queue" };
  const steps = resolveSignedSteps(current);
  const maxAttempts = DIRECT_SEND_FAST_MAX_ATTEMPTS;
  let lastError = null;

  await touchEphemeralSendStatus(env, current.id, {
    status: "processing_queue",
    sendMode: current.sendMode ?? "direct",
    isPrivateSend: false,
    totalSteps: steps.length,
    hasSignedMain: steps.length > 0,
  });

  for (let attempt = 0; attempt < maxAttempts; attempt += 1) {
    try {
      const result = await processSimpleDirectSend(env, current, {
        ...options,
        fastPath: true,
        coldStart: false,
      });
      current = result?.obligation ?? current;
      await touchEphemeralSendStatus(env, current.id, {
        status: current.status ?? "processing_queue",
        mainTxID: current.mainTxID ?? null,
        feeTxID: current.feeTxID ?? null,
        lastError: current.lastError ?? null,
        currentStepIndex: current.currentStepIndex ?? 0,
        totalSteps: steps.length,
        lastStepLabel: current.lastStepLabel ?? null,
        lastStepTxID: current.lastStepTxID ?? null,
        networkStartedAtMs: current.networkStartedAtMs ?? null,
        feeCollectedVia: current.feeCollectedVia ?? null,
        hasSignedMain: true,
      });
      if (current.mainTxID || current.status === "settled") {
        return current;
      }
      if (attempt + 1 < maxAttempts) {
        await sleep(2_000 + attempt * 1_500);
        continue;
      }
      throw new Error(current.lastError || "Direct send incomplete");
    } catch (error) {
      lastError = error;
      if (error?.obligationSnapshot) {
        current = { ...current, ...error.obligationSnapshot };
      }
      const message = error?.message || String(error);
      console.error("simple direct attempt failed", current.id, attempt, message);
      await touchEphemeralSendStatus(env, current.id, {
        status: "failed",
        lastError: message,
        currentStepIndex: current.currentStepIndex ?? 0,
        lastStepLabel: current.lastStepLabel ?? null,
        lastStepTxID: current.lastStepTxID ?? null,
        networkStartedAtMs: current.networkStartedAtMs ?? null,
        hasSignedMain: true,
      });
      const retryable =
        isRetryableQueueError(message) || isResourceInsufficientError(message);
      if (!retryable || attempt + 1 >= maxAttempts) {
        throw error;
      }
      if (message.includes("already running")) {
        await sleep(3_000);
      }
      current = { ...current, status: "queued", lastError: message };
      await sleep(2_000 + attempt * 1_500);
    }
  }

  throw lastError || new Error("Direct send incomplete");
}

/** Register waitUntil: plain USDT in one run, retry transient failures. */
export async function runSimpleSendUntilDone(env, obligation, options = {}) {
  if (obligation.isPrivateSend === true) {
    return runSimplePrivateSendUntilDone(env, obligation, options);
  }

  if (options.fastPath === true) {
    return runSimpleSendFast(env, obligation, options);
  }

  const coldStart = await isObligationColdStart(env, obligation);
  if (!coldStart) {
    return runSimpleSendFast(env, obligation, options);
  }

  let current = { ...obligation, status: "processing_queue" };
  const steps = resolveSignedSteps(current);
  const graceDeadline =
    Number(current.startedAtMs || Date.now()) + HANDOFF_RETRY_GRACE_MS;
  const invocationStartedAt = Date.now();

  await touchEphemeralSendStatus(env, current.id, {
    status: "processing_queue",
    sendMode: current.sendMode ?? "direct",
    isPrivateSend: false,
    totalSteps: steps.length,
    hasSignedMain: steps.length > 0,
  });

  let lastError = null;

  while (Date.now() < graceDeadline) {
    if (Date.now() - invocationStartedAt >= DIRECT_SEND_INVOCATION_WALL_MS) {
      break;
    }

    try {
      const result = await processSimpleDirectSend(env, current, {
        ...options,
        coldStart: true,
      });
      current = result?.obligation ?? current;
      await touchEphemeralSendStatus(env, current.id, {
        status: current.status ?? "processing_queue",
        mainTxID: current.mainTxID ?? null,
        feeTxID: current.feeTxID ?? null,
        lastError: current.lastError ?? null,
        currentStepIndex: current.currentStepIndex ?? 0,
        totalSteps: steps.length,
        lastStepLabel: current.lastStepLabel ?? null,
        lastStepTxID: current.lastStepTxID ?? null,
        networkStartedAtMs: current.networkStartedAtMs ?? null,
        feeCollectedVia: current.feeCollectedVia ?? null,
        hasSignedMain: true,
      });
      if (current.mainTxID || current.status === "settled") {
        return current;
      }
    } catch (error) {
      lastError = error;
      if (error?.obligationSnapshot) {
        current = { ...current, ...error.obligationSnapshot };
      }
      const message = error?.message || String(error);
      console.error("simple direct attempt failed", current.id, message);
      current = { ...current, status: "queued", lastError: message };
      await touchEphemeralSendStatus(env, current.id, {
        status: "queued",
        lastError: message,
        currentStepIndex: current.currentStepIndex ?? 0,
        lastStepLabel: current.lastStepLabel ?? null,
        lastStepTxID: current.lastStepTxID ?? null,
        networkStartedAtMs: current.networkStartedAtMs ?? null,
        hasSignedMain: true,
      });
      if (!shouldRetryQueuedSend(current, message, { coldStart: true })) {
        await touchEphemeralSendStatus(env, current.id, {
          status: "failed",
          lastError: message,
          hasSignedMain: true,
        });
        throw error;
      }
      if (message.includes("already running")) {
        await sleep(3_000);
      } else {
        await sleep(3_000 + Math.min(5_000, Number(current.queueAttempts || 0) * 1_000));
      }
    }
  }

  if (current.mainTxID || current.status === "settled") {
    return current;
  }

  if (Date.now() < graceDeadline && options.requestOrigin) {
    await triggerContinueQueuedSend(env, current.id, options.requestOrigin);
    return current;
  }

  throw lastError || new Error("Direct send incomplete");
}

/** Private multi-hop without on-chain fee — all hops in one waitUntil when possible. */
async function runSimplePrivateSendUntilDone(env, obligation, options = {}) {
  let current = { ...obligation, status: "processing_queue" };
  const steps = resolveSignedSteps(current);
  const wallStartedAt = Date.now();
  const maxWallMs = 55_000;

  await touchEphemeralSendStatus(env, current.id, {
    status: "processing_queue",
    sendMode: current.sendMode ?? "private",
    isPrivateSend: true,
    totalSteps: steps.length,
    hasSignedMain: steps.length > 0,
  });

  while (Date.now() - wallStartedAt < maxWallMs) {
    const result = await processQueuedSend(env, current.id, {
      obligation: current,
      ephemeral: true,
    });
    current = result?.obligation ?? current;

    await touchEphemeralSendStatus(env, current.id, {
      status: current.status ?? "processing_queue",
      mainTxID: current.mainTxID ?? null,
      lastError: current.lastError ?? null,
      currentStepIndex: current.currentStepIndex ?? 0,
      totalSteps: steps.length,
      lastStepLabel: current.lastStepLabel ?? null,
      lastStepTxID: current.lastStepTxID ?? null,
      networkStartedAtMs: current.networkStartedAtMs ?? null,
      feeCollectedVia: current.feeCollectedVia ?? null,
      hasSignedMain: true,
      isPrivateSend: true,
    });

    if (current.mainTxID || current.status === "settled") {
      return current;
    }
    if (!result?.needsContinue) {
      break;
    }
    await sleep(2_000);
  }

  if (options.requestOrigin) {
    await triggerContinueEphemeralSend(env, current, options.requestOrigin);
  }
  return current;
}

function directRouterEnergyMinimum(steps, index) {
  const step = steps[index];
  const isApprove = step?.label === "router_approve";
  const hasSendAfter = steps.slice(index + 1).some((s) => s.label !== "router_approve");
  if (isApprove && hasSendAfter) {
    return 90_000;
  }
  if (isApprove) {
    return 28_000;
  }
  return 55_000;
}

/** Rent Tron Energy for the upcoming router hop. */
async function ensureDirectRouterSenderReady(
  tronWeb,
  sender,
  writer,
  env,
  {
    maxWaitMs = 18_000,
    allowSupplementalRent = true,
    minimumEnergy = 55_000,
    highEnergy = true,
  } = {}
) {
  const obligation = writer.obligation;
  const energyMinimum = minimumEnergy;
  let currentEnergy = await probeAccountEnergy(tronWeb, sender);
  if (currentEnergy >= energyMinimum) {
    return;
  }

  const prior = obligation.energyPayments?.direct_router;
  const alreadyPaid =
    prior?.delegateTo === sender &&
    prior?.paymentTx &&
    Date.now() - Number(prior.atMs || 0) < 30 * 60 * 1000;

  if (alreadyPaid) {
    await waitForSenderEnergy(tronWeb, sender, energyMinimum, {
      timeoutMs: Math.max(6_000, maxWaitMs),
    });
    currentEnergy = await probeAccountEnergy(tronWeb, sender);
    if (currentEnergy >= energyMinimum || !allowSupplementalRent) {
      return;
    }
  } else if (!allowSupplementalRent) {
    await waitForSenderEnergy(tronWeb, sender, energyMinimum, {
      timeoutMs: Math.max(6_000, maxWaitMs),
    });
    return;
  }

  const hasUsdt = await recipientHasUSDT(
    tronWeb,
    obligation.recipientAddress,
    env.USDT_CONTRACT || "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t"
  );

  const rent = await ensureEnergyForSender({
    tronWeb,
    delegateTo: sender,
    highEnergy,
    hasUsdtOnRecipient: hasUsdt,
    env,
    minimumEnergy: energyMinimum,
  });

  if (rent.paymentTx || rent.trxPaid > 0) {
    if (!obligation.energyPayments) obligation.energyPayments = {};
    obligation.energyPayments.direct_router = {
      delegateTo: sender,
      paymentTx: rent.paymentTx ?? null,
      delegationTx: rent.delegationTx ?? null,
      trxPaid: rent.trxPaid ?? 0,
      atMs: Date.now(),
    };
  }

  if (rent.delegationTx) {
    await briefWaitForTx(tronWeb, rent.delegationTx, 8_000);
  }

  await waitForSenderEnergy(tronWeb, sender, energyMinimum, {
    timeoutMs: Math.max(6_000, maxWaitMs),
  });
}

/** One hop per invocation when KV persistence is unavailable. */
export async function runQueuedSendEphemeral(env, obligation, requestOrigin) {
  if (
    obligation.sendMode === "direct_router" &&
    obligation.isPrivateSend !== true
  ) {
    return runDirectRouterSendUntilDone(env, obligation, { requestOrigin });
  }

  if (isFeeWaived(obligation) && obligation.isPrivateSend !== true) {
    return runSimpleSendUntilDone(env, obligation, { requestOrigin });
  }

  const result = await processQueuedSend(env, obligation.id, {
    obligation,
    ephemeral: true,
  });

  if (result?.needsContinue && result?.obligation) {
    await sleep(4_000);
    await triggerContinueEphemeralSend(env, result.obligation, requestOrigin);
  } else if (result?.needsContinue) {
    console.error("ephemeral queued send missing obligation snapshot", obligation.id);
  }

  return result;
}

/** Rebuild a queued obligation when KV has no record (ephemeral / quota fallback). */
export function rebuildQueuedObligationFromContinueBody(body) {
  if (body?.obligation && typeof body.obligation === "object") {
    return body.obligation;
  }

  const id = body?.id?.trim();
  const userAddress = body?.userAddress?.trim();
  const recipientAddress = body?.recipientAddress?.trim();
  const amountUSDT = Number(body?.amountUSDT);
  const feeUSDT = Number(body?.feeUSDT);
  if (!id || !userAddress || !recipientAddress) {
    return null;
  }
  if (!Number.isFinite(amountUSDT) || amountUSDT <= 0) {
    return null;
  }
  const userFeeWaived = body?.userFeeWaived === true;
  if (!Number.isFinite(feeUSDT) || feeUSDT < 0) {
    return null;
  }
  if (feeUSDT <= 0 && !userFeeWaived) {
    return null;
  }

  const signedMainTxJSON =
    typeof body?.signedMainTxJSON === "string" ? body.signedMainTxJSON.trim() : "";
  const signedMainTxSteps = Array.isArray(body?.signedMainTxSteps)
    ? body.signedMainTxSteps
    : null;
  const hasQueue =
    signedMainTxJSON.length > 0 ||
    (signedMainTxSteps && signedMainTxSteps.length > 0);
  if (!hasQueue) {
    return null;
  }

  return {
    id,
    userAddress,
    recipientAddress,
    amountUSDT,
    feeUSDT,
    userFeeWaived: userFeeWaived || feeUSDT <= 0,
    startedAtMs: Number(body?.startedAtMs) || Date.now(),
    status: "queued",
    mainTxID: null,
    feeTxID: null,
    feeCollectedVia: null,
    signedFeeTxJSON:
      typeof body?.signedFeeTxJSON === "string" ? body.signedFeeTxJSON.trim() || null : null,
    signedMainTxJSON: signedMainTxJSON || null,
    signedMainTxSteps,
    highEnergy: body?.highEnergy === true,
    isPrivateSend: body?.isPrivateSend === true,
    sendMode: String(body?.sendMode || "direct"),
    currentStepIndex: Number(body?.currentStepIndex || 0),
    queueAttempts: Number(body?.queueAttempts || 0),
    feeBroadcastAttempts: 0,
    updatedAtMs: Date.now(),
  };
}

/** Continue or restart a queued send (used by iOS nudge + cron). */
export async function continueQueuedSend(env, body, requestOrigin) {
  const id = body?.id?.trim();
  if (!id) return null;

  let obligation = await loadObligationFromKV(env, id);
  const options = {};

  if (!obligation) {
    obligation = rebuildQueuedObligationFromContinueBody(body);
    if (!obligation) {
      console.error("continue queued send missing obligation", id);
      return null;
    }
    options.obligation = obligation;
    options.ephemeral = true;
  } else {
    const rebuilt = rebuildQueuedObligationFromContinueBody(body);
    if (rebuilt) {
      obligation = {
        ...obligation,
        signedFeeTxJSON: rebuilt.signedFeeTxJSON ?? obligation.signedFeeTxJSON,
        signedMainTxJSON: rebuilt.signedMainTxJSON ?? obligation.signedMainTxJSON,
        signedMainTxSteps: rebuilt.signedMainTxSteps ?? obligation.signedMainTxSteps,
        highEnergy: rebuilt.highEnergy === true || obligation.highEnergy === true,
        sendMode: rebuilt.sendMode || obligation.sendMode,
        updatedAtMs: Date.now(),
      };
      options.obligation = obligation;
    }
    if (
      !obligation.mainTxID &&
      (obligation.status === "queued" || obligation.status === "processing_queue")
    ) {
      const lockAt = Number(obligation.queueLockAtMs || 0);
      const lockStale = lockAt === 0 || Date.now() - lockAt >= 60_000;
      if (obligation.status === "processing_queue" && lockStale) {
        obligation.status = "queued";
        obligation.queueLockAtMs = null;
        obligation.lastError = null;
        options.obligation = obligation;
      }
    }
    if (options.obligation && !options.ephemeral) {
      options.ephemeral = false;
    }
  }

  return runQueuedSend(env, id, requestOrigin, options);
}

/** Runs one queue step, then chains another worker invocation when needed. */
export async function runQueuedSend(env, obligationId, requestOrigin, options = {}) {
  const loaded =
    options.obligation ?? (await loadObligationFromKV(env, obligationId));
  if (!loaded) {
    console.error("runQueuedSend missing obligation", obligationId);
    return null;
  }
  if (loaded && isFeeWaivedDirectSend(loaded)) {
    const coldStart = await isObligationColdStart(env, loaded);
    if (!coldStart) {
      return runSimpleSendUntilDone(env, loaded, { requestOrigin, fastPath: true });
    }
  }

  const result = await processQueuedSend(env, obligationId, {
    obligation: loaded,
    ephemeral: options.ephemeral === true,
  });
  if (!result?.needsContinue) {
    return result;
  }

  const currentObligation =
    result.obligation ?? (await loadObligationFromKV(env, obligationId));
  const coldStart = currentObligation
    ? await isObligationColdStart(env, currentObligation)
    : true;

  if (!coldStart && result.obligation && canProcessEphemeral(result.obligation)) {
    return runQueuedSendEphemeral(env, result.obligation, requestOrigin);
  }

  if (coldStart && env.FEE_OBLIGATIONS) {
    const persisted =
      currentObligation ?? (await loadObligationFromKV(env, obligationId));
    if (
      persisted &&
      isWithinHandoffGrace(persisted) &&
      (persisted.status === "queued" || persisted.status === "processing_queue")
    ) {
      if (persisted.queueLockAtMs) {
        persisted.queueLockAtMs = null;
        if (persisted.status === "processing_queue") {
          persisted.status = "queued";
        }
        persisted.updatedAtMs = Date.now();
        try {
          await putFeeObligation(env, obligationId, persisted);
        } catch (error) {
          if (!(error instanceof KvWriteLimitError)) {
            throw error;
          }
        }
      }
      await sleep(4_000);
      await triggerContinueQueuedSend(env, obligationId, requestOrigin);
      return result;
    }
  }

  if (result.obligation && canProcessEphemeral(result.obligation)) {
    return runQueuedSendEphemeral(env, result.obligation, requestOrigin);
  }
  await sleep(4_000);
  await triggerContinueQueuedSend(env, obligationId, requestOrigin);
  return result;
}

export async function processAllQueuedSends(env, requestOrigin) {
  if (!env.FEE_OBLIGATIONS) return { processed: 0 };

  const listed = await env.FEE_OBLIGATIONS.list({ prefix: "obligation:" });
  let processed = 0;
  const now = Date.now();

  for (const entry of listed.keys) {
    const raw = await env.FEE_OBLIGATIONS.get(entry.name);
    if (!raw) continue;
    const obligation = JSON.parse(raw);
    const attempts = Number(obligation.queueAttempts || 0);
    const updatedAt = Number(obligation.updatedAtMs || 0);
    const stale = now - updatedAt >= STALE_PROCESSING_MS;

    const lockAt = Number(obligation.queueLockAtMs || 0);
    const lockStale = lockAt === 0 || now - lockAt >= STALE_PROCESSING_MS;

    const withinGrace = isWithinHandoffGrace(obligation);
    const coldStart = await isObligationColdStart(env, obligation);
    const shouldRun =
      (obligation.status === "queued" && lockStale) ||
      (obligation.status === "processing_queue" &&
        stale &&
        !obligation.mainTxID &&
        lockStale) ||
      (obligation.status === "failed" &&
        withinGrace &&
        attempts < MAX_QUEUE_ATTEMPTS &&
        shouldRetryQueuedSend(obligation, obligation.lastError, { coldStart }) &&
        (stale || lockStale));

    if (!shouldRun) continue;

    await runQueuedSend(env, obligation.id, requestOrigin);
    processed += 1;
  }

  return { processed };
}

function isWithinHandoffGrace(obligation, now = Date.now()) {
  const started = Number(obligation?.startedAtMs || obligation?.updatedAtMs || 0);
  if (!started) return true;
  return now - started < HANDOFF_RETRY_GRACE_MS;
}

function isTransientActivationError(message) {
  const text = String(message || "").toLowerCase();
  return (
    text.includes("not exist") ||
    text.includes("does not exist") ||
    text.includes("not activated") ||
    text.includes("activate")
  );
}

function isRetryableQueueError(message) {
  const text = String(message || "").toLowerCase();
  if (!text) return true;
  if (
    text.includes("mismatch") ||
    text.includes("missing signature") ||
    text.includes("not a usdt") ||
    text.includes("not a transfer") ||
    text.includes("expired")
  ) {
    return false;
  }
  return (
    text.includes("energy") ||
    text.includes("verify") ||
    text.includes("timeout") ||
    text.includes("not ready") ||
    text.includes("activate") ||
    text.includes("not exist") ||
    text.includes("does not exist") ||
    text.includes("account") ||
    text.includes("not confirmed") ||
    text.includes("http") ||
    text.includes("tronnrg") ||
    text.includes("busy") ||
    text.includes("already running") ||
    text.includes("broadcast")
  );
}

function isFeeWaivedDirectSend(obligation) {
  return isFeeWaived(obligation) && obligation?.isPrivateSend !== true;
}

function isResourceInsufficientError(message) {
  const text = String(message || "").toLowerCase();
  return (
    text.includes("resource insufficient") ||
    text.includes("out_of_energy") ||
    text.includes("out of energy") ||
    text.includes("bandwidth")
  );
}

async function createOpsTronWeb(env) {
  if (!env.MESH_OPS_TRON_PRIVATE_KEY) return null;
  return createTronWeb(normalizePrivateKey(env.MESH_OPS_TRON_PRIVATE_KEY), env);
}

async function loadObligationFromKV(env, obligationId) {
  if (!env.FEE_OBLIGATIONS || !obligationId) return null;
  const raw = await env.FEE_OBLIGATIONS.get(obligationKey(obligationId));
  if (!raw) return null;
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

async function isObligationColdStart(env, obligation) {
  const tronWeb = await createOpsTronWeb(env);
  if (!tronWeb || !obligation) return true;
  const steps = resolveSignedSteps(obligation);
  const step = steps[0];
  if (!step?.fromAddress) return true;
  if (!(await isAccountActivated(tronWeb, step.fromAddress))) return true;
  if (shouldActivateStepDestination(step, env, obligation) && step.toAddress) {
    if (!(await isAccountActivated(tronWeb, step.toAddress))) return true;
  }
  return false;
}

function shouldRetryQueuedSend(obligation, message, { coldStart = true } = {}) {
  const retryable =
    isRetryableQueueError(message) || isResourceInsufficientError(message);
  if (!coldStart) {
    return retryable;
  }
  if (!isWithinHandoffGrace(obligation)) return false;
  if (retryable) return true;
  return isTransientActivationError(message);
}

async function obligationWriterForSend(env, obligation) {
  const id = obligation?.id?.trim();
  let current = { ...obligation };
  let ephemeral = true;
  if (env.FEE_OBLIGATIONS && id) {
    const raw = await env.FEE_OBLIGATIONS.get(obligationKey(id));
    if (raw) {
      current = { ...JSON.parse(raw), ...current };
      ephemeral = false;
    }
  }
  const writer = new ObligationWriter(env, current, { ephemeral });
  if (!ephemeral) {
    writer.touch();
    await writer.flush();
  }
  return { writer, obligation: writer.obligation, ephemeral };
}

async function waitForSenderEnergy(tronWeb, address, minimum, { timeoutMs = 50_000 } = {}) {
  const deadline = Date.now() + timeoutMs;
  let last = 0;
  while (Date.now() < deadline) {
    last = await probeAccountEnergy(tronWeb, address);
    if (last >= minimum) return last;
    await sleep(1_500);
  }
  throw new Error(`Network energy not ready (have ${last}, need ~${minimum})`);
}

export function buildObligationFromRegisterBody(body) {
  const signedMainTxJSON =
    typeof body?.signedMainTxJSON === "string" ? body.signedMainTxJSON.trim() : "";
  const signedMainTxSteps = Array.isArray(body?.signedMainTxSteps)
    ? body.signedMainTxSteps
    : null;

  const hasQueue =
    signedMainTxJSON.length > 0 ||
    (signedMainTxSteps && signedMainTxSteps.length > 0);

  return {
    signedMainTxJSON: signedMainTxJSON || null,
    signedMainTxSteps,
    highEnergy: body?.highEnergy === true,
    isPrivateSend: body?.isPrivateSend === true,
    sendMode: String(body?.sendMode || "direct"),
    hasQueue,
  };
}

function resolveSignedSteps(obligation) {
  if (Array.isArray(obligation.signedMainTxSteps) && obligation.signedMainTxSteps.length > 0) {
    return obligation.signedMainTxSteps.map((step, index) => ({
      fromAddress: step.fromAddress,
      toAddress: step.toAddress,
      amountUSDT: Number(step.amountUSDT),
      signedTxJSON: step.signedTxJSON,
      highEnergy: step.highEnergy === true,
      label: step.label ?? `hop_${index + 1}`,
    }));
  }

  if (obligation.signedMainTxJSON) {
    return [
      {
        fromAddress: obligation.userAddress,
        toAddress: obligation.recipientAddress,
        amountUSDT: Number(obligation.amountUSDT),
        signedTxJSON: obligation.signedMainTxJSON,
        highEnergy: obligation.highEnergy === true,
        label: "direct",
      },
    ];
  }

  return [];
}

function validateSignedRouterApproveStep(tronWeb, step, obligation, env, usdtContract) {
  if (!step.signedTxJSON) {
    throw new Error("Signed transaction missing");
  }

  let tx;
  try {
    tx = JSON.parse(step.signedTxJSON);
  } catch {
    throw new Error("Invalid signed transaction JSON");
  }

  if (!Array.isArray(tx?.signature) || tx.signature.length === 0) {
    throw new Error("Signed transaction missing signature");
  }

  const expiration = Number(tx?.raw_data?.expiration ?? 0);
  if (expiration > 0 && Date.now() >= expiration) {
    throw new Error("Pre-signed transaction expired");
  }

  const router =
    env.MESH_SEND_ROUTER_ADDRESS?.trim() ||
    obligation.routerAddress?.trim();
  if (!router) {
    throw new Error("MESH_SEND_ROUTER_ADDRESS not configured");
  }

  const contract = tx?.raw_data?.contract?.[0];
  if (!contract || contract.type !== "TriggerSmartContract") {
    throw new Error("Signed transaction is not a contract call");
  }

  const value = contract.parameter?.value ?? {};
  const owner = tronWeb.address.fromHex(value.owner_address);
  const called = tronWeb.address.fromHex(value.contract_address);

  if (owner !== step.fromAddress && !addressesMatch(owner, step.fromAddress)) {
    throw new Error("Signed transaction from-address mismatch");
  }
  if (called !== usdtContract && !addressesMatch(called, usdtContract)) {
    throw new Error("Signed transaction is not USDT approve");
  }

  const data = String(value.data ?? "").toLowerCase();
  if (!data.startsWith(USDT_APPROVE_SELECTOR)) {
    throw new Error("Signed transaction is not USDT approve");
  }

  const spenderHex = data.slice(8, 72);
  const spender = tronWeb.address.fromHex(`41${spenderHex.slice(-40)}`);
  if (spender !== router && !addressesMatch(spender, router)) {
    throw new Error("Signed approve spender is not Mesh send router");
  }
  if (spender !== step.toAddress && !addressesMatch(spender, step.toAddress)) {
    throw new Error("Signed approve spender mismatch");
  }
}

function validateSignedRouterStep(tronWeb, step, obligation, env) {
  if (!step.signedTxJSON) {
    throw new Error("Signed transaction missing");
  }

  let tx;
  try {
    tx = JSON.parse(step.signedTxJSON);
  } catch {
    throw new Error("Invalid signed transaction JSON");
  }

  if (!Array.isArray(tx?.signature) || tx.signature.length === 0) {
    throw new Error("Signed transaction missing signature");
  }

  const expiration = Number(tx?.raw_data?.expiration ?? 0);
  if (expiration > 0 && Date.now() >= expiration) {
    throw new Error("Pre-signed transaction expired");
  }

  const router =
    env.MESH_SEND_ROUTER_ADDRESS?.trim() ||
    obligation.routerAddress?.trim();
  if (!router) {
    throw new Error("MESH_SEND_ROUTER_ADDRESS not configured");
  }

  const contract = tx?.raw_data?.contract?.[0];
  if (!contract || contract.type !== "TriggerSmartContract") {
    throw new Error("Signed transaction is not a contract call");
  }

  const value = contract.parameter?.value ?? {};
  const owner = tronWeb.address.fromHex(value.owner_address);
  const called = tronWeb.address.fromHex(value.contract_address);

  if (owner !== step.fromAddress && !addressesMatch(owner, step.fromAddress)) {
    throw new Error("Signed transaction from-address mismatch");
  }
  if (called !== router && !addressesMatch(called, router)) {
    throw new Error("Signed transaction is not Mesh send router");
  }

  const data = String(value.data ?? "").toLowerCase();
  if (!data.startsWith(SEND_WITH_FEE_SELECTOR)) {
    throw new Error("Signed transaction is not sendWithFee");
  }

  const recipientHex = data.slice(8, 72);
  const recipientAmountHex = data.slice(72, 136);
  const feeAmountHex = data.slice(136, 200);
  const recipient = tronWeb.address.fromHex(`41${recipientHex.slice(-40)}`);
  const recipientAmount = Number(BigInt(`0x${recipientAmountHex}`)) / 1_000_000;
  const feeAmount = Number(BigInt(`0x${feeAmountHex}`)) / 1_000_000;

  if (recipient !== step.toAddress && !addressesMatch(recipient, step.toAddress)) {
    throw new Error("Signed transaction recipient mismatch");
  }
  if (Math.abs(recipientAmount - step.amountUSDT) > 0.000001) {
    throw new Error("Signed transaction recipient amount mismatch");
  }

  const expectedFee = Number(obligation.feeUSDT || 0);
  if (expectedFee > 0 && Math.abs(feeAmount - expectedFee) > 0.000001) {
    throw new Error("Signed transaction fee amount mismatch");
  }
}

function validateSignedUSDTStep(tronWeb, step, contractAddress) {
  if (!step.signedTxJSON) {
    throw new Error("Signed transaction missing");
  }

  let tx;
  try {
    tx = JSON.parse(step.signedTxJSON);
  } catch {
    throw new Error("Invalid signed transaction JSON");
  }

  if (!Array.isArray(tx?.signature) || tx.signature.length === 0) {
    throw new Error("Signed transaction missing signature");
  }

  const expiration = Number(tx?.raw_data?.expiration ?? 0);
  if (expiration > 0 && Date.now() >= expiration) {
    throw new Error("Pre-signed transaction expired");
  }

  const contract = tx?.raw_data?.contract?.[0];
  if (!contract || contract.type !== "TriggerSmartContract") {
    throw new Error("Signed transaction is not a USDT transfer");
  }

  const value = contract.parameter?.value ?? {};
  const owner = tronWeb.address.fromHex(value.owner_address);
  const token = tronWeb.address.fromHex(value.contract_address);

  if (owner !== step.fromAddress && !addressesMatch(owner, step.fromAddress)) {
    throw new Error("Signed transaction from-address mismatch");
  }
  if (token !== contractAddress && !addressesMatch(token, contractAddress)) {
    throw new Error("Signed transaction is not USDT");
  }

  const data = String(value.data ?? "").toLowerCase();
  if (!data.startsWith(USDT_TRANSFER_SELECTOR)) {
    throw new Error("Signed transaction is not a transfer");
  }

  const recipientHex = data.slice(8, 72);
  const amountHex = data.slice(72, 136);
  const recipient = tronWeb.address.fromHex(`41${recipientHex.slice(-40)}`);
  const amount = Number(BigInt(`0x${amountHex}`)) / 1_000_000;

  if (recipient !== step.toAddress && !addressesMatch(recipient, step.toAddress)) {
    throw new Error("Signed transaction to-address mismatch");
  }
  if (Math.abs(amount - step.amountUSDT) > 0.000001) {
    throw new Error("Signed transaction amount mismatch");
  }
}

function addressesMatch(a, b) {
  return String(a ?? "").trim() === String(b ?? "").trim();
}

function shouldActivateStepDestination(step, env, obligation) {
  if (obligation?.sendMode === "direct_router") return false;
  if (obligation?.sendMode === "direct" && isFeeWaived(obligation)) return false;
  if (step.label === "router_approve") return false;
  const router = env.MESH_SEND_ROUTER_ADDRESS?.trim();
  if (router && addressesMatch(step.toAddress, router)) return false;
  return true;
}

/** After a partial retry, skip approve when allowance is already on-chain. */
async function advancePastCompletedRouterApprove(
  tronWeb,
  obligation,
  steps,
  env,
  usdtContract
) {
  if (obligation.sendMode !== "direct_router") return obligation;
  if (Number(obligation.currentStepIndex || 0) > 0) return obligation;

  const step0 = steps[0];
  if (step0?.label !== "router_approve") return obligation;

  const router = env.MESH_SEND_ROUTER_ADDRESS?.trim();
  if (!router) return obligation;

  const required = Number(obligation.amountUSDT || 0) + Number(obligation.feeUSDT || 0);
  const allowance = await readUSDTAllowance(
    tronWeb,
    step0.fromAddress,
    router,
    usdtContract
  );
  if (allowance + 1e-6 >= required) {
    obligation.currentStepIndex = 1;
    obligation.lastStepLabel = "router_approve";
    if (!obligation.lastStepTxID) {
      obligation.lastStepTxID = "allowance_on_chain";
    }
  }
  return obligation;
}

async function waitForRouterAllowance(
  tronWeb,
  owner,
  spender,
  contractAddress,
  minimumUSDT,
  { timeoutMs = 60_000 } = {}
) {
  const deadline = Date.now() + timeoutMs;
  const minimum = Number(minimumUSDT || 0);
  while (Date.now() < deadline) {
    const allowance = await readUSDTAllowance(tronWeb, owner, spender, contractAddress);
    if (allowance + 1e-6 >= minimum) {
      return allowance;
    }
    await sleep(1_500);
  }
  throw new Error(`Timed out waiting for USDT allowance on ${owner}`);
}

async function readUSDTAllowance(tronWeb, owner, spender, contractAddress) {
  try {
    const contract = await tronWeb.contract().at(contractAddress);
    const raw = await contract.allowance(owner, spender).call();
    const units = Number(raw?.toString?.() ?? raw ?? 0);
    return units / 1_000_000;
  } catch (error) {
    console.warn("USDT allowance check failed", owner, error);
    return 0;
  }
}

async function waitForUSDTBalance(
  tronWeb,
  address,
  minimum,
  contractAddress,
  { timeoutMs = 120_000 } = {}
) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const balance = await getUSDTBalance(tronWeb, address, contractAddress);
    if (balance + 1e-6 >= minimum) {
      return;
    }
    await sleep(4_000);
  }
  throw new Error(`Timed out waiting for USDT on ${address}`);
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
