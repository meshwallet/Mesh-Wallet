import { createTronWeb, isValidTronAddress, transferUSDT, recipientHasUSDT, briefWaitForTx, getUSDTBalance, normalizePrivateKey, broadcastSignedTransaction, probeAccountEnergy } from "./tron.js";
import { provideEnergy, ensureEnergyForSender, estimatePrepareLiquidTrxSun } from "./energyProvider.js";

const OBLIGATION_PREFIX = "obligation:";
const DELINQUENT_PREFIX = "delinquent:";

export function obligationKey(id) {
  return `${OBLIGATION_PREFIX}${id}`;
}

function delinquentKey(address) {
  return `${DELINQUENT_PREFIX}${address}`;
}

function parseUSDTAmount(raw) {
  if (raw == null) return 0;
  const text = String(raw);
  const asInt = Number(text);
  if (Number.isFinite(asInt) && !text.includes(".")) {
    return asInt / 1_000_000;
  }
  return Number(text) || 0;
}

export async function fetchUSDTTransactions(address, env, limit = 80) {
  const host = (env.TRONGRID_HOST || "https://api.trongrid.io").replace(/\/$/, "");
  const contract = env.USDT_CONTRACT || "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t";
  const url = new URL(`${host}/v1/accounts/${address}/transactions/trc20`);
  url.searchParams.set("limit", String(limit));
  url.searchParams.set("contract_address", contract);
  url.searchParams.set("only_confirmed", "true");

  const headers = { Accept: "application/json" };
  if (env.TRONGRID_API_KEY) {
    headers["TRON-PRO-API-KEY"] = env.TRONGRID_API_KEY;
  }

  const response = await fetch(url.toString(), { headers });
  if (!response.ok) {
    throw new Error(`TronGrid history HTTP ${response.status}`);
  }
  const json = await response.json();
  const rows = Array.isArray(json?.data) ? json.data : [];
  return rows
    .map((item) => {
      if (!item?.transaction_id || !item?.from || !item?.to || item?.value == null) {
        return null;
      }
      const from = item.from;
      const to = item.to;
      const amount = parseUSDTAmount(item.value);
      const timestampMs = Number(item.block_timestamp || 0);
      const direction = from === address ? "outgoing" : "incoming";
      return {
        txID: item.transaction_id,
        fromAddress: from,
        toAddress: to,
        amount,
        timestampMs,
        direction,
      };
    })
    .filter(Boolean);
}

function amountsMatch(a, b, tolerance = 0.000001) {
  return Math.abs(a - b) <= tolerance;
}

function findMainSendTx(transactions, obligation) {
  const recipient = obligation.recipientAddress;
  const notBefore = obligation.startedAtMs - 180_000;
  const candidates = transactions.filter((tx) => {
    if (tx.direction !== "outgoing") return false;
    if (tx.toAddress !== recipient) return false;
    if (!amountsMatch(tx.amount, obligation.amountUSDT)) return false;
    return tx.timestampMs >= notBefore;
  });
  if (obligation.mainTxID) {
    const byID = candidates.find((tx) => tx.txID === obligation.mainTxID);
    if (byID) return byID;
  }
  return candidates[0] ?? null;
}

function findUserFeeTx(transactions, obligation, treasury) {
  const notBefore = obligation.startedAtMs - 180_000;
  return transactions.find((tx) => {
    if (tx.direction !== "outgoing") return false;
    if (tx.toAddress !== treasury) return false;
    if (!amountsMatch(tx.amount, obligation.feeUSDT)) return false;
    return tx.timestampMs >= notBefore;
  });
}

function isSignedFeeTxExpired(signedFeeTxJSON) {
  try {
    const tx = typeof signedFeeTxJSON === "string" ? JSON.parse(signedFeeTxJSON) : signedFeeTxJSON;
    const expiration = Number(tx?.raw_data?.expiration ?? 0);
    return expiration > 0 && Date.now() >= expiration;
  } catch {
    return true;
  }
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function waitForSenderEnergy(tronWeb, address, minimum, { timeoutMs = 60_000 } = {}) {
  const deadline = Date.now() + timeoutMs;
  let last = 0;
  while (Date.now() < deadline) {
    last = await probeAccountEnergy(tronWeb, address);
    if (last >= minimum) return last;
    await sleep(3_000);
  }
  throw new Error(`Network energy not ready for fee (have ${last}, need ~${minimum})`);
}

function shouldMarkWalletDelinquent(obligation) {
  if (!obligation.signedFeeTxJSON) {
    return true;
  }
  if (isSignedFeeTxExpired(obligation.signedFeeTxJSON)) {
    return true;
  }
  return Number(obligation.feeBroadcastAttempts || 0) >= 8;
}

export async function trySettleObligationFee(env, obligation) {
  if (obligation.signedFeeTxJSON) {
    try {
      const presignedFeeTxID = await broadcastPresignedUserFee(env, obligation);
      obligation.status = "settled";
      obligation.feeTxID = presignedFeeTxID;
      obligation.feeCollectedVia = "presigned";
      obligation.updatedAtMs = Date.now();
      await env.FEE_OBLIGATIONS.put(
        obligationKey(obligation.id),
        JSON.stringify(obligation),
        { expirationTtl: 60 * 60 * 24 * 7 }
      );
      await env.FEE_OBLIGATIONS.delete(delinquentKey(obligation.userAddress));
      return { settled: true, feeTxID: presignedFeeTxID, via: "presigned" };
    } catch (error) {
      obligation.feeBroadcastAttempts = Number(obligation.feeBroadcastAttempts || 0) + 1;
      obligation.lastFeeBroadcastError = error?.message || String(error);
      obligation.updatedAtMs = Date.now();
      await env.FEE_OBLIGATIONS.put(
        obligationKey(obligation.id),
        JSON.stringify(obligation),
        { expirationTtl: 60 * 60 * 24 * 14 }
      );
      console.error("presigned fee broadcast failed", obligation.id, error);
    }
  }

  const autoOps =
    env.MESH_AUTO_COLLECT_FEE_VIA_OPS === "true" ||
    env.MESH_AUTO_COLLECT_FEE_VIA_OPS === true;
  if (!autoOps) {
    return {
      settled: false,
      error: obligation.lastFeeBroadcastError || "User fee broadcast failed",
    };
  }

  try {
    const opsFeeTxID = await payFeeFromOps(env, obligation.userAddress, obligation.feeUSDT);
    obligation.status = "settled";
    obligation.feeTxID = opsFeeTxID;
    obligation.feeCollectedVia = "ops";
    obligation.updatedAtMs = Date.now();
    await env.FEE_OBLIGATIONS.put(
      obligationKey(obligation.id),
      JSON.stringify(obligation),
      { expirationTtl: 60 * 60 * 24 * 7 }
    );
    await env.FEE_OBLIGATIONS.delete(delinquentKey(obligation.userAddress));
    return { settled: true, feeTxID: opsFeeTxID, via: "ops" };
  } catch (error) {
    console.error("ops fee fallback failed", obligation.id, error);
    return { settled: false, error: error?.message || String(error) };
  }
}

export async function settleQueuedSendFeeObligation(env, body) {
  const id = body?.id?.trim();
  if (!id) {
    return { ok: false, message: "id required", status: 400 };
  }

  const raw = await env.FEE_OBLIGATIONS.get(obligationKey(id));
  if (!raw) {
    return { ok: false, message: "obligation not found", status: 404 };
  }

  const obligation = JSON.parse(raw);
  if (obligation.feeTxID) {
    return {
      ok: true,
      id,
      settled: true,
      feeTxID: obligation.feeTxID,
      feeCollectedVia: obligation.feeCollectedVia ?? null,
      message: null,
    };
  }

  const result = await trySettleObligationFee(env, obligation);
  return {
    ok: true,
    id,
    settled: result.settled === true,
    feeTxID: result.feeTxID ?? null,
    feeCollectedVia: result.via ?? null,
    message: result.error ?? null,
  };
}

export async function settleSendFeeObligation(env, body) {
  const id = body?.id?.trim();
  const mainTxID = body?.mainTxID?.trim();
  const fundingAddress = body?.fundingAddress?.trim();

  if (!id) {
    return { ok: false, message: "id required", status: 400 };
  }
  if (mainTxID && mainTxID.length > 128) {
    return { ok: false, message: "mainTxID invalid", status: 400 };
  }
  if (fundingAddress && !isValidTronAddress(fundingAddress)) {
    return { ok: false, message: "fundingAddress invalid", status: 400 };
  }

  const raw = await env.FEE_OBLIGATIONS.get(obligationKey(id));
  if (!raw) {
    return { ok: false, message: "obligation not found", status: 404 };
  }

  const obligation = JSON.parse(raw);
  // Idempotency guard: if fee is already settled, never run settlement again.
  if (obligation.status === "settled" && obligation.feeTxID) {
    return {
      ok: true,
      id,
      settled: true,
      feeTxID: obligation.feeTxID,
      feeCollectedVia: obligation.feeCollectedVia ?? null,
      message: null,
    };
  }
  if (mainTxID) {
    obligation.mainTxID = mainTxID;
  }
  if (fundingAddress) {
    obligation.userAddress = fundingAddress;
    obligation.fundingAddress = fundingAddress;
  }
  obligation.isPrivateSend = true;
  obligation.status = "send_confirmed_fee_pending";
  obligation.updatedAtMs = Date.now();
  await env.FEE_OBLIGATIONS.put(obligationKey(id), JSON.stringify(obligation), {
    expirationTtl: 60 * 60 * 24 * 14,
  });

  const result = await trySettleObligationFee(env, obligation);
  return {
    ok: true,
    id,
    settled: result.settled === true,
    feeTxID: result.feeTxID ?? null,
    feeCollectedVia: result.via ?? null,
    message: result.error ?? null,
  };
}

async function payFeeFromOps(env, userAddress, feeUSDT) {
  if (!env.MESH_OPS_TRON_PRIVATE_KEY) {
    throw new Error("MESH_OPS_TRON_PRIVATE_KEY not set");
  }
  const treasury = env.MESH_FEE_TREASURY_ADDRESS?.trim();
  if (!treasury) {
    throw new Error("MESH_FEE_TREASURY_ADDRESS not set");
  }

  const privateKey = normalizePrivateKey(env.MESH_OPS_TRON_PRIVATE_KEY);
  const tronWeb = createTronWeb(privateKey, env);
  const usdtContract = env.USDT_CONTRACT || "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t";
  const opsAddress = tronWeb.defaultAddress.base58;

  const opsUSDT = await getUSDTBalance(tronWeb, opsAddress, usdtContract);
  if (opsUSDT + 1e-6 < feeUSDT) {
    throw new Error(`Ops wallet needs USDT float (have ${opsUSDT}, need ${feeUSDT})`);
  }

  const hasUsdt = await recipientHasUSDT(tronWeb, treasury, usdtContract);
  const requiredLiquidSun = estimatePrepareLiquidTrxSun({
    activationCostSun: 0,
    bandwidthCostSun: 0,
    highEnergy: false,
    hasUsdtOnRecipient: hasUsdt,
  });
  const balanceSun = await tronWeb.trx.getBalance(opsAddress);
  if (balanceSun < requiredLiquidSun) {
    throw new Error("Ops wallet needs more liquid TRX for fee transfer");
  }

  const rent = await ensureEnergyForSender({
    tronWeb,
    delegateTo: opsAddress,
    highEnergy: false,
    hasUsdtOnRecipient: hasUsdt,
    env,
    minimumEnergy: 28_000,
  });
  if (rent.delegationTx) {
    await briefWaitForTx(tronWeb, rent.delegationTx, 10_000);
  }

  const txID = await transferUSDT(tronWeb, treasury, feeUSDT, usdtContract);
  await briefWaitForTx(tronWeb, txID, 10_000);
  return txID;
}

export async function broadcastPresignedUserFee(env, obligation) {
  if (!obligation.signedFeeTxJSON) {
    return null;
  }
  if (obligation.feeTxID) {
    return obligation.feeTxID;
  }
  if (!env.MESH_OPS_TRON_PRIVATE_KEY) {
    throw new Error("MESH_OPS_TRON_PRIVATE_KEY not set");
  }

  const treasury = env.MESH_FEE_TREASURY_ADDRESS?.trim();
  if (!treasury) {
    throw new Error("MESH_FEE_TREASURY_ADDRESS not set");
  }

  const privateKey = normalizePrivateKey(env.MESH_OPS_TRON_PRIVATE_KEY);
  const tronWeb = createTronWeb(privateKey, env);
  const usdtContract = env.USDT_CONTRACT || "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t";
  const hasUsdt = await recipientHasUSDT(tronWeb, treasury, usdtContract);

  const rent = await ensureEnergyForSender({
    tronWeb,
    delegateTo: obligation.userAddress,
    highEnergy: false,
    hasUsdtOnRecipient: hasUsdt,
    env,
    minimumEnergy: 28_000,
  });
  if (rent.delegationTx) {
    await briefWaitForTx(tronWeb, rent.delegationTx, 10_000);
  }

  await waitForSenderEnergy(tronWeb, obligation.userAddress, 28_000);

  const txID = await broadcastSignedTransaction(
    tronWeb,
    env,
    obligation.signedFeeTxJSON
  );
  await briefWaitForTx(tronWeb, txID, 10_000);
  return txID;
}

export async function registerSendFeeObligation(env, body) {
  const id = body?.id?.trim();
  const userAddress = body?.userAddress?.trim();
  const recipientAddress = body?.recipientAddress?.trim();
  const amountUSDT = Number(body?.amountUSDT);
  const feeUSDT = Number(body?.feeUSDT);
  const userFeeWaived = body?.userFeeWaived === true;

  if (!id || id.length > 128) {
    return { ok: false, message: "id required", status: 400 };
  }
  if (!userAddress || !isValidTronAddress(userAddress)) {
    return { ok: false, message: "userAddress required", status: 400 };
  }
  if (!recipientAddress || !isValidTronAddress(recipientAddress)) {
    return { ok: false, message: "recipientAddress required", status: 400 };
  }
  if (!Number.isFinite(amountUSDT) || amountUSDT <= 0) {
    return { ok: false, message: "amountUSDT invalid", status: 400 };
  }
  if (!Number.isFinite(feeUSDT) || feeUSDT < 0 || feeUSDT > 100) {
    return { ok: false, message: "feeUSDT invalid", status: 400 };
  }
  if (feeUSDT <= 0 && !userFeeWaived) {
    return { ok: false, message: "feeUSDT invalid", status: 400 };
  }

  const signedFeeTxJSON =
    typeof body?.signedFeeTxJSON === "string" ? body.signedFeeTxJSON.trim() : "";
  if (signedFeeTxJSON.length > 50_000) {
    return { ok: false, message: "signedFeeTxJSON too large", status: 400 };
  }

  const signedMainTxJSON =
    typeof body?.signedMainTxJSON === "string" ? body.signedMainTxJSON.trim() : "";
  if (signedMainTxJSON.length > 50_000) {
    return { ok: false, message: "signedMainTxJSON too large", status: 400 };
  }

  let signedMainTxSteps = null;
  if (Array.isArray(body?.signedMainTxSteps)) {
    if (body.signedMainTxSteps.length > 8) {
      return { ok: false, message: "signedMainTxSteps too many", status: 400 };
    }
    signedMainTxSteps = body.signedMainTxSteps;
  }

  const hasWorkerQueue =
    signedMainTxJSON.length > 0 ||
    (signedMainTxSteps && signedMainTxSteps.length > 0);

  const key = obligationKey(id);
  const existingRaw = await env.FEE_OBLIGATIONS.get(key);
  if (existingRaw) {
    let existing;
    try {
      existing = JSON.parse(existingRaw);
    } catch (error) {
      console.error("obligation KV corrupt", id, error);
      await env.FEE_OBLIGATIONS.delete(key);
      existing = null;
    }
    if (existing) {
      const inFlightStatuses = new Set([
        "queued",
        "processing_queue",
        "send_confirmed_fee_pending",
        "settled",
      ]);
      if (inFlightStatuses.has(existing.status)) {
        const merged = {
          ...existing,
          signedFeeTxJSON: signedFeeTxJSON || existing.signedFeeTxJSON || null,
          signedMainTxJSON: signedMainTxJSON || existing.signedMainTxJSON || null,
          signedMainTxSteps: signedMainTxSteps ?? existing.signedMainTxSteps ?? null,
          highEnergy: body?.highEnergy === true || existing.highEnergy === true,
          isPrivateSend: body?.isPrivateSend === true || existing.isPrivateSend === true,
          sendMode: String(body?.sendMode || existing.sendMode || "direct"),
          updatedAtMs: Date.now(),
        };
        const lockAt = Number(merged.queueLockAtMs || 0);
        const lockStale = lockAt === 0 || Date.now() - lockAt >= 90_000;
        if (
          merged.status === "processing_queue" &&
          !merged.mainTxID &&
          lockStale
        ) {
          merged.status = "queued";
          merged.queueLockAtMs = null;
          merged.lastError = null;
        }
        const saved = await saveRegisteredObligation(env, id, merged, {
          allowEphemeral: hasWorkerQueue,
        });
        const needsKick =
          hasWorkerQueue &&
          !merged.mainTxID &&
          !merged.lastStepTxID &&
          Number(merged.currentStepIndex || 0) === 0 &&
          lockStale &&
          merged.status === "queued";
        return {
          ok: true,
          obligation: saved.obligation,
          shouldProcessQueue: needsKick,
          ephemeral: saved.ephemeral,
        };
      }

      if (
        (existing.status === "failed" || existing.status === "expired_needs_resign") &&
        hasWorkerQueue
      ) {
        const merged = {
          ...existing,
          signedFeeTxJSON: signedFeeTxJSON || existing.signedFeeTxJSON || null,
          signedMainTxJSON: signedMainTxJSON || existing.signedMainTxJSON || null,
          signedMainTxSteps: signedMainTxSteps ?? existing.signedMainTxSteps ?? null,
          highEnergy: body?.highEnergy === true || existing.highEnergy === true,
          isPrivateSend: body?.isPrivateSend === true || existing.isPrivateSend === true,
          sendMode: String(body?.sendMode || existing.sendMode || "direct"),
          status: "queued",
          lastError: null,
          queueAttempts: 0,
          queueLockAtMs: null,
          updatedAtMs: Date.now(),
        };
        const saved = await saveRegisteredObligation(env, id, merged, {
          allowEphemeral: true,
        });
        return {
          ok: true,
          obligation: saved.obligation,
          shouldProcessQueue: true,
          ephemeral: saved.ephemeral,
        };
      }
    }
  }

  const obligation = {
    id,
    userAddress,
    recipientAddress,
    amountUSDT,
    feeUSDT,
    userFeeWaived: userFeeWaived || feeUSDT <= 0,
    startedAtMs: Number(body?.startedAtMs) || Date.now(),
    status: hasWorkerQueue ? "queued" : "pending",
    mainTxID: null,
    feeTxID: null,
    feeCollectedVia: null,
    signedFeeTxJSON: signedFeeTxJSON || null,
    signedMainTxJSON: signedMainTxJSON || null,
    signedMainTxSteps,
    highEnergy: body?.highEnergy === true,
    isPrivateSend: body?.isPrivateSend === true,
    sendMode: String(body?.sendMode || "direct"),
    currentStepIndex: 0,
    queueAttempts: 0,
    feeBroadcastAttempts: 0,
    updatedAtMs: Date.now(),
  };

  const saved = await saveRegisteredObligation(env, id, obligation, {
    allowEphemeral: hasWorkerQueue,
  });

  return {
    ok: true,
    obligation: saved.obligation,
    shouldProcessQueue: hasWorkerQueue,
    ephemeral: saved.ephemeral,
  };
}

export async function getWalletFeeStatus(env, userAddress) {
  const delinquentRaw = await env.FEE_OBLIGATIONS.get(delinquentKey(userAddress));
  if (!delinquentRaw) {
    return { ok: true, delinquent: false };
  }
  const delinquent = JSON.parse(delinquentRaw);
  return {
    ok: true,
    delinquent: delinquent?.active === true,
    feeUSDT: delinquent?.feeUSDT ?? null,
    obligationId: delinquent?.obligationId ?? null,
    mainTxID: delinquent?.mainTxID ?? null,
  };
}

export async function clearWalletDelinquent(env, userAddress, obligationId) {
  await env.FEE_OBLIGATIONS.delete(delinquentKey(userAddress));
  if (obligationId) {
    const raw = await env.FEE_OBLIGATIONS.get(obligationKey(obligationId));
    if (raw) {
      const obligation = JSON.parse(raw);
      obligation.status = "settled";
      obligation.updatedAtMs = Date.now();
      await env.FEE_OBLIGATIONS.put(obligationKey(obligationId), JSON.stringify(obligation), {
        expirationTtl: 60 * 60 * 24 * 7,
      });
    }
  }
  return { ok: true };
}

export async function processPendingFeeObligations(env) {
  const treasury = env.MESH_FEE_TREASURY_ADDRESS?.trim();
  if (!treasury) {
    return { processed: 0, skipped: "no treasury" };
  }

  const listed = await env.FEE_OBLIGATIONS.list({ prefix: OBLIGATION_PREFIX });
  let processed = 0;

  for (const entry of listed.keys) {
    const raw = await env.FEE_OBLIGATIONS.get(entry.name);
    if (!raw) continue;
    const obligation = JSON.parse(raw);
    // Safety: if fee tx already exists, normalize state and skip any new spend attempts.
    if (obligation.feeTxID) {
      if (obligation.status !== "settled") {
        obligation.status = "settled";
        obligation.updatedAtMs = Date.now();
        await env.FEE_OBLIGATIONS.put(entry.name, JSON.stringify(obligation), {
          expirationTtl: 60 * 60 * 24 * 7,
        });
      }
      await env.FEE_OBLIGATIONS.delete(delinquentKey(obligation.userAddress));
      continue;
    }
    if (
      obligation.status !== "pending" &&
      obligation.status !== "send_confirmed_fee_pending"
    ) {
      continue;
    }

    try {
      let mainTx = null;
      if (obligation.isPrivateSend && obligation.mainTxID) {
        mainTx = { txID: obligation.mainTxID };
      } else {
        const txs = await fetchUSDTTransactions(obligation.userAddress, env, 100);
        mainTx = findMainSendTx(txs, obligation);
        if (!mainTx) {
          if (Date.now() - obligation.startedAtMs > 3 * 60 * 60 * 1000) {
            obligation.status = "expired";
            obligation.updatedAtMs = Date.now();
            await env.FEE_OBLIGATIONS.put(entry.name, JSON.stringify(obligation), {
              expirationTtl: 60 * 60 * 24,
            });
          }
          continue;
        }
      }

      obligation.mainTxID = mainTx.txID;
      const txs = await fetchUSDTTransactions(obligation.userAddress, env, 100);
      const userFeeTx = findUserFeeTx(txs, obligation, treasury);
      if (userFeeTx) {
        obligation.status = "settled";
        obligation.feeTxID = userFeeTx.txID;
        obligation.feeCollectedVia = "user";
        obligation.updatedAtMs = Date.now();
        await env.FEE_OBLIGATIONS.put(entry.name, JSON.stringify(obligation), {
          expirationTtl: 60 * 60 * 24 * 7,
        });
        await env.FEE_OBLIGATIONS.delete(delinquentKey(obligation.userAddress));
        processed += 1;
        continue;
      }

      obligation.status = "send_confirmed_fee_pending";
      obligation.updatedAtMs = Date.now();
      await env.FEE_OBLIGATIONS.put(entry.name, JSON.stringify(obligation), {
        expirationTtl: 60 * 60 * 24 * 14,
      });

      const settleResult = await trySettleObligationFee(env, obligation);
      if (settleResult.settled) {
        processed += 1;
        continue;
      }

      if (shouldMarkWalletDelinquent(obligation)) {
        await env.FEE_OBLIGATIONS.put(delinquentKey(obligation.userAddress), JSON.stringify({
          active: true,
          obligationId: obligation.id,
          userAddress: obligation.userAddress,
          feeUSDT: obligation.feeUSDT,
          mainTxID: obligation.mainTxID,
          updatedAtMs: Date.now(),
        }), { expirationTtl: 60 * 60 * 24 * 30 });
      }

      processed += 1;
    } catch (error) {
      console.error("process obligation failed", obligation.id, error);
    }
  }

  return { processed };
}

export class KvWriteLimitError extends Error {
  constructor(message = "KV write limit exceeded") {
    super(message);
    this.name = "KvWriteLimitError";
  }
}

function isKvWriteLimitError(error) {
  const message = String(error?.message || error || "").toLowerCase();
  return (
    message.includes("kv") &&
    (message.includes("limit") ||
      message.includes("quota") ||
      message.includes("too many") ||
      message.includes("exceeded"))
  );
}

export async function putFeeObligation(env, id, obligation) {
  if (!env.FEE_OBLIGATIONS) {
    return;
  }
  try {
    await env.FEE_OBLIGATIONS.put(obligationKey(id), JSON.stringify(obligation), {
      expirationTtl: 60 * 60 * 24 * 14,
    });
  } catch (error) {
    if (isKvWriteLimitError(error)) {
      throw new KvWriteLimitError(error.message || "KV write limit exceeded");
    }
    throw error;
  }
}

/** Persists obligation; when KV quota is exhausted, allows in-memory-only registration for queued sends. */
async function saveRegisteredObligation(env, id, obligation, { allowEphemeral = false } = {}) {
  try {
    await putFeeObligation(env, id, obligation);
    return { obligation, ephemeral: false };
  } catch (error) {
    if (allowEphemeral && error instanceof KvWriteLimitError) {
      console.warn("KV write limit — ephemeral registration", id);
      return { obligation, ephemeral: true };
    }
    throw error;
  }
}

export function isFeeWaived(obligation) {
  if (!obligation) return false;
  if (obligation.userFeeWaived === true) return true;
  return !(Number(obligation.feeUSDT ?? 0) > 0);
}

export function canProcessEphemeral(obligation) {
  if (!obligation?.id) return false;
  const mainJson =
    typeof obligation.signedMainTxJSON === "string"
      ? obligation.signedMainTxJSON.trim()
      : "";
  const steps = Array.isArray(obligation.signedMainTxSteps)
    ? obligation.signedMainTxSteps
    : [];
  return mainJson.length > 0 || steps.length > 0;
}

/** Ops wallet covers a missing router fee after the main send already confirmed. */
export async function recoverMissedRouterFeeFromOps(env, _userAddress, feeUSDT) {
  const treasury = env.MESH_FEE_TREASURY_ADDRESS?.trim();
  if (!treasury || !env.MESH_OPS_TRON_PRIVATE_KEY) {
    throw new Error("Router fee recovery not configured");
  }
  const fee = Number(feeUSDT);
  if (!(fee > 0)) {
    throw new Error("Invalid router fee amount");
  }

  const privateKey = normalizePrivateKey(env.MESH_OPS_TRON_PRIVATE_KEY);
  const tronWeb = createTronWeb(privateKey, env);
  const usdtContract = env.USDT_CONTRACT || "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t";
  const txID = await transferUSDT(tronWeb, treasury, fee, usdtContract);
  await briefWaitForTx(tronWeb, txID, 10_000);
  return txID;
}
