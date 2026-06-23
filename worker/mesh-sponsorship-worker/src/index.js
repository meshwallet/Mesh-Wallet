import {
  createTronWeb,
  isValidTronAddress,
  normalizePrivateKey,
  recipientHasUSDT,
  needsActivation,
  ensureAccountActivated,
  probeAccountEnergy,
  ensureSenderBandwidth,
  briefWaitForTx,
  BANDWIDTH_TOPUP_TRX_SUN,
  getUSDTBalance,
  transferUSDT,
  ACTIVATION_TRX_SUN,
} from "./tron.js";
import {
  ensureEnergyForSender,
  estimatePrepareLiquidTrxSun,
  energyProviderName,
  prepareEnergyMinimum,
} from "./energyProvider.js";
import {
  registerSendFeeObligation,
  getWalletFeeStatus,
  clearWalletDelinquent,
  processPendingFeeObligations,
  settleSendFeeObligation,
  settleQueuedSendFeeObligation,
  KvWriteLimitError,
} from "./feeObligations.js";
import {
  processQueuedSend,
  processAllQueuedSends,
  getSendObligationStatus,
  runQueuedSend,
  continueQueuedSend,
} from "./sendQueue.js";

export default {
  async scheduled(event, env, ctx) {
    ctx.waitUntil(
      (async () => {
        await processAllQueuedSends(env);
        await processPendingFeeObligations(env);
      })().catch((error) => {
        console.error("scheduled send queue failed", error);
      })
    );
  },

  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, { headers: corsHeaders() });
    }

    if (url.pathname === "/health" || url.pathname === "/v1/health") {
      return json({ ok: true, service: "mesh-sponsorship-relay" });
    }

    if (url.pathname === "/v1/activate" && request.method === "POST") {
      return handleActivate(request, env);
    }

    if (url.pathname === "/v1/prepare-sender" && request.method === "POST") {
      return handlePrepareSender(request, env);
    }

    if (url.pathname === "/v1/pay-network-fee" && request.method === "POST") {
      return handlePayNetworkFee(request, env);
    }

    if (url.pathname === "/v1/ops-status" && request.method === "GET") {
      return handleOpsStatus(request, env);
    }

    if (url.pathname === "/v1/register-send-fee" && request.method === "POST") {
      return handleRegisterSendFee(request, env, ctx);
    }

    if (url.pathname === "/v1/settle-send-fee" && request.method === "POST") {
      return handleSettleSendFee(request, env);
    }

    if (url.pathname === "/v1/settle-queued-send-fee" && request.method === "POST") {
      return handleSettleQueuedSendFee(request, env);
    }

    if (url.pathname === "/v1/wallet-fee-status" && request.method === "GET") {
      return handleWalletFeeStatus(request, env);
    }

    if (url.pathname === "/v1/send-status" && request.method === "GET") {
      return handleSendStatus(request, env);
    }

    if (url.pathname === "/v1/continue-queued-send" && request.method === "POST") {
      return handleContinueQueuedSend(request, env, ctx);
    }

    if (url.pathname === "/v1/clear-wallet-delinquent" && request.method === "POST") {
      return handleClearWalletDelinquent(request, env);
    }

    return json({ ok: false, message: "Not found" }, 404);
  },
};

async function handleActivate(request, env) {
  if (env.RELAY_AUTH_SECRET) {
    const auth = request.headers.get("Authorization") ?? "";
    if (auth !== `Bearer ${env.RELAY_AUTH_SECRET}`) {
      return json({ ok: false, message: "Unauthorized" }, 401);
    }
  }

  let body;
  try {
    body = await request.json();
  } catch {
    return json({ ok: false, message: "Invalid JSON" }, 400);
  }

  const address = body?.address?.trim();
  if (!address) {
    return json({ ok: false, message: "address required" }, 400);
  }
  if (!isValidTronAddress(address)) {
    return json({ ok: false, message: "Invalid Tron address" }, 400);
  }
  if (!env.MESH_OPS_TRON_PRIVATE_KEY) {
    return json({ ok: false, message: "Relay not configured" }, 503);
  }

  try {
    const tronWeb = createTronWeb(normalizePrivateKey(env.MESH_OPS_TRON_PRIVATE_KEY), env);
    const opsAddress = tronWeb.defaultAddress.base58;
    const balanceSun = await tronWeb.trx.getBalance(opsAddress);
    if (balanceSun < ACTIVATION_TRX_SUN + 200_000) {
      return json({ ok: false, message: "Ops wallet needs TRX for activation" }, 503);
    }

    const tx = await ensureAccountActivated(tronWeb, address, {
      maxChecks: 18,
      intervalMs: 4_000,
    });

    return json({ ok: true, address, activated: true, tx });
  } catch (error) {
    console.error("activate failed", error);
    return json(
      { ok: false, message: error?.message || "Activation failed" },
      500
    );
  }
}

async function handlePrepareSender(request, env) {
  if (env.RELAY_AUTH_SECRET) {
    const auth = request.headers.get("Authorization") ?? "";
    if (auth !== `Bearer ${env.RELAY_AUTH_SECRET}`) {
      return json({ ok: false, message: "Unauthorized" }, 401);
    }
  }

  let body;
  try {
    body = await request.json();
  } catch {
    return json({ ok: false, message: "Invalid JSON" }, 400);
  }

  const address = body?.address?.trim();
  const toAddress = body?.toAddress?.trim();
  if (!address || !toAddress) {
    return json({ ok: false, message: "address and toAddress required" }, 400);
  }

  if (!isValidTronAddress(address) || !isValidTronAddress(toAddress)) {
    return json({ ok: false, message: "Invalid Tron address" }, 400);
  }

  if (!env.MESH_OPS_TRON_PRIVATE_KEY) {
    return json(
      {
        ok: false,
        message:
          "Relay not configured. Set MESH_OPS_TRON_PRIVATE_KEY with wrangler secret.",
      },
      503
    );
  }

  try {
    const privateKey = normalizePrivateKey(env.MESH_OPS_TRON_PRIVATE_KEY);
    const tronWeb = createTronWeb(privateKey, env);
    const usdtContract =
      env.USDT_CONTRACT || "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t";

    const hasUsdt = await recipientHasUSDT(tronWeb, toAddress, usdtContract);
    const highEnergy = body?.highEnergy === true;

    const opsAddress = tronWeb.defaultAddress.base58;
    const skipRecipientActivation = body?.skipRecipientActivation === true;

    let activationCostSun = 0;
    if (await needsActivation(tronWeb, address, usdtContract)) {
      activationCostSun += ACTIVATION_TRX_SUN;
    }
    if (!skipRecipientActivation && (await needsActivation(tronWeb, toAddress, usdtContract))) {
      activationCostSun += ACTIVATION_TRX_SUN;
    }

    const senderBalanceSun = await tronWeb.trx.getBalance(address);
    const bandwidthCostSun =
      senderBalanceSun < BANDWIDTH_TOPUP_TRX_SUN ? BANDWIDTH_TOPUP_TRX_SUN : 0;

    const energyMinimum = prepareEnergyMinimum({ highEnergy });
    const currentEnergy = await probeAccountEnergy(tronWeb, address);
    const needsEnergyRent = currentEnergy < energyMinimum;

    const requiredLiquidSun = estimatePrepareLiquidTrxSun({
      activationCostSun,
      bandwidthCostSun,
      highEnergy,
      hasUsdtOnRecipient: hasUsdt,
      skipEnergyRent: !needsEnergyRent,
    });

    const balanceSun = await tronWeb.trx.getBalance(opsAddress);
    if (balanceSun < requiredLiquidSun) {
      const provider = energyProviderName();
      return json(
        {
          ok: false,
          message: `Ops wallet needs more liquid TRX (have ${(balanceSun / 1e6).toFixed(1)}, need ~${(requiredLiquidSun / 1e6).toFixed(1)} TRX for ${provider} prepare)`,
        },
        503
      );
    }

    const activations = [];
    const activationTx = await ensureAccountActivated(tronWeb, address, {
      maxChecks: 8,
      intervalMs: 3_500,
    });
    if (activationTx) {
      activations.push({ address, tx: activationTx });
    }
    if (!skipRecipientActivation) {
      const recipientTx = await ensureAccountActivated(tronWeb, toAddress, {
        maxChecks: 8,
        intervalMs: 3_500,
      });
      if (recipientTx) {
        activations.push({ address: toAddress, tx: recipientTx });
      }
    }

    let bandwidthTopupTx = null;
    for (let attempt = 0; attempt < 3; attempt += 1) {
      try {
        bandwidthTopupTx = await ensureSenderBandwidth(tronWeb, address);
        break;
      } catch (topupError) {
        console.warn("bandwidth topup failed", attempt + 1, topupError);
        if (attempt >= 2) {
          throw topupError;
        }
        await new Promise((resolve) => setTimeout(resolve, 3_000));
      }
    }

    let result = await ensureEnergyForSender({
      tronWeb,
      delegateTo: address,
      highEnergy,
      hasUsdtOnRecipient: hasUsdt,
      env,
      minimumEnergy: energyMinimum,
    });

    if (result.delegationTx) {
      await briefWaitForTx(tronWeb, result.delegationTx, 10_000);
    }

    const onChainEnergy = await probeAccountEnergy(tronWeb, address);

    return json({
      ok: true,
      delegateTo: address,
      toAddress,
      energyProvider: result.source,
      trxPaid: result.trxPaid,
      energySkipped: result.skipped === true,
      energy: onChainEnergy || result.energy,
      paymentTx: result.paymentTx,
      delegationTx: result.delegationTx,
      tronnrgRef: result.tronnrgRef,
      activations,
      bandwidthTopupTx,
    });
  } catch (error) {
    console.error("prepare-sender failed", error);
    return json(
      {
        ok: false,
        message: error?.message || "Energy preparation failed",
      },
      500
    );
  }
}

/**
 * Ops wallet sends the USDT network fee to treasury (user wallet does not spend energy on fee).
 */
async function handlePayNetworkFee(request, env) {
  if (env.RELAY_AUTH_SECRET) {
    const auth = request.headers.get("Authorization") ?? "";
    if (auth !== `Bearer ${env.RELAY_AUTH_SECRET}`) {
      return json({ ok: false, message: "Unauthorized" }, 401);
    }
  }

  let body;
  try {
    body = await request.json();
  } catch {
    return json({ ok: false, message: "Invalid JSON" }, 400);
  }

  const userAddress = body?.userAddress?.trim();
  const feeUSDT = Number(body?.feeUSDT);
  const treasury =
    body?.treasury?.trim() || env.MESH_FEE_TREASURY_ADDRESS?.trim();

  if (!userAddress || !isValidTronAddress(userAddress)) {
    return json({ ok: false, message: "userAddress required" }, 400);
  }
  if (!treasury || !isValidTronAddress(treasury)) {
    return json({ ok: false, message: "treasury address not configured" }, 400);
  }
  if (!Number.isFinite(feeUSDT) || feeUSDT <= 0 || feeUSDT > 100) {
    return json({ ok: false, message: "feeUSDT must be between 0 and 100" }, 400);
  }

  if (!env.MESH_OPS_TRON_PRIVATE_KEY) {
    return json(
      {
        ok: false,
        message: "Relay not configured. Set MESH_OPS_TRON_PRIVATE_KEY.",
      },
      503
    );
  }

  try {
    const privateKey = normalizePrivateKey(env.MESH_OPS_TRON_PRIVATE_KEY);
    const tronWeb = createTronWeb(privateKey, env);
    const usdtContract =
      env.USDT_CONTRACT || "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t";
    const opsAddress = tronWeb.defaultAddress.base58;

    const opsUSDT = await getUSDTBalance(tronWeb, opsAddress, usdtContract);
    if (opsUSDT + 1e-6 < feeUSDT) {
      return json(
        {
          ok: false,
          message: `Ops wallet needs USDT float (have ${opsUSDT.toFixed(2)}, need ${feeUSDT} USDT fee)`,
        },
        503
      );
    }

    const hasUsdt = await recipientHasUSDT(tronWeb, treasury, usdtContract);
    const feeEnergyMinimum = prepareEnergyMinimum({ highEnergy: false });
    const opsEnergy = await probeAccountEnergy(tronWeb, opsAddress);
    const needsOpsEnergyRent = opsEnergy < feeEnergyMinimum;

    const requiredLiquidSun = estimatePrepareLiquidTrxSun({
      activationCostSun: 0,
      bandwidthCostSun: 0,
      highEnergy: false,
      hasUsdtOnRecipient: hasUsdt,
      skipEnergyRent: !needsOpsEnergyRent,
    });

    const balanceSun = await tronWeb.trx.getBalance(opsAddress);
    if (balanceSun < requiredLiquidSun) {
      return json(
        {
          ok: false,
          message: `Ops wallet needs more liquid TRX for fee transfer (have ${(balanceSun / 1e6).toFixed(1)} TRX)`,
        },
        503
      );
    }

    const rent = await ensureEnergyForSender({
      tronWeb,
      delegateTo: opsAddress,
      highEnergy: false,
      hasUsdtOnRecipient: hasUsdt,
      env,
      minimumEnergy: feeEnergyMinimum,
    });
    if (rent.delegationTx) {
      await briefWaitForTx(tronWeb, rent.delegationTx, 10_000);
    }

    const txID = await transferUSDT(tronWeb, treasury, feeUSDT, usdtContract);
    await briefWaitForTx(tronWeb, txID, 10_000);

    return json({
      ok: true,
      txID,
      userAddress,
      treasury,
      feeUSDT,
      paidBy: "ops",
    });
  } catch (error) {
    console.error("pay-network-fee failed", error);
    return json(
      {
        ok: false,
        message: error?.message || "Failed to pay network fee",
      },
      500
    );
  }
}

async function handleRegisterSendFee(request, env, ctx) {
  const authError = requireRelayAuth(request, env);
  if (authError) return authError;

  if (!env.FEE_OBLIGATIONS) {
    return json({ ok: false, message: "FEE_OBLIGATIONS KV not configured" }, 503);
  }

  let body;
  try {
    body = await request.json();
  } catch {
    return json({ ok: false, message: "Invalid JSON" }, 400);
  }

  let result;
  try {
    result = await registerSendFeeObligation(env, body);
  } catch (error) {
    console.error("register-send-fee failed", error);
    if (error instanceof KvWriteLimitError) {
      return json(
        {
          ok: false,
          message:
            "Send service is temporarily at capacity. Please try again in a few hours.",
        },
        503
      );
    }
    return json(
      {
        ok: false,
        message: error?.message || "Failed to register send",
      },
      500
    );
  }

  if (!result.ok) {
    return json({ ok: false, message: result.message }, result.status || 400);
  }

  const obligation = result.obligation;
  if (!obligation?.id) {
    console.error("register-send-fee missing obligation", result);
    return json({ ok: false, message: "Send registration incomplete" }, 500);
  }

  if (result.shouldProcessQueue && obligation.status === "queued") {
    const origin = new URL(request.url).origin;
    const runOptions = result.ephemeral ? { obligation } : {};
    ctx.waitUntil(
      runQueuedSend(env, obligation.id, origin, runOptions).catch((error) => {
        console.error("queued send failed", obligation.id, error);
      })
    );
  }

  return json({
    ok: true,
    id: obligation.id,
    queued: obligation.status === "queued",
  });
}

async function handleSettleQueuedSendFee(request, env) {
  const authError = requireRelayAuth(request, env);
  if (authError) return authError;

  if (!env.FEE_OBLIGATIONS) {
    return json({ ok: false, message: "FEE_OBLIGATIONS KV not configured" }, 503);
  }

  let body;
  try {
    body = await request.json();
  } catch {
    return json({ ok: false, message: "Invalid JSON" }, 400);
  }

  const result = await settleQueuedSendFeeObligation(env, body);
  if (!result.ok) {
    return json({ ok: false, message: result.message }, result.status || 400);
  }
  return json(result);
}

async function handleSettleSendFee(request, env) {
  const authError = requireRelayAuth(request, env);
  if (authError) return authError;

  if (!env.FEE_OBLIGATIONS) {
    return json({ ok: false, message: "FEE_OBLIGATIONS KV not configured" }, 503);
  }

  let body;
  try {
    body = await request.json();
  } catch {
    return json({ ok: false, message: "Invalid JSON" }, 400);
  }

  const result = await settleSendFeeObligation(env, body);
  if (!result.ok) {
    return json({ ok: false, message: result.message }, result.status || 400);
  }
  return json(result);
}

async function handleContinueQueuedSend(request, env, ctx) {
  const authError = requireRelayAuth(request, env);
  if (authError) return authError;

  let body;
  try {
    body = await request.json();
  } catch {
    return json({ ok: false, message: "Invalid JSON" }, 400);
  }

  const id = body?.id?.trim();
  if (!id) {
    return json({ ok: false, message: "id required" }, 400);
  }

  const origin = new URL(request.url).origin;
  ctx.waitUntil(
    continueQueuedSend(env, body, origin).catch((error) => {
      console.error("continue queued send failed", id, error);
    })
  );

  return json({ ok: true });
}

async function handleWalletFeeStatus(request, env) {
  const authError = requireRelayAuth(request, env);
  if (authError) return authError;

  if (!env.FEE_OBLIGATIONS) {
    return json({ ok: false, message: "FEE_OBLIGATIONS KV not configured" }, 503);
  }

  const userAddress = new URL(request.url).searchParams.get("address")?.trim();
  if (!userAddress || !isValidTronAddress(userAddress)) {
    return json({ ok: false, message: "address query required" }, 400);
  }

  const status = await getWalletFeeStatus(env, userAddress);
  return json(status);
}

async function handleSendStatus(request, env) {
  const authError = requireRelayAuth(request, env);
  if (authError) return authError;

  if (!env.FEE_OBLIGATIONS) {
    return json({ ok: false, message: "FEE_OBLIGATIONS KV not configured" }, 503);
  }

  const id = new URL(request.url).searchParams.get("id")?.trim();
  if (!id) {
    return json({ ok: false, message: "id query required" }, 400);
  }

  const status = await getSendObligationStatus(env, id);
  if (!status.ok) {
    return json(status, 404);
  }
  return json(status);
}

async function handleClearWalletDelinquent(request, env) {
  const authError = requireRelayAuth(request, env);
  if (authError) return authError;

  if (!env.FEE_OBLIGATIONS) {
    return json({ ok: false, message: "FEE_OBLIGATIONS KV not configured" }, 503);
  }

  let body;
  try {
    body = await request.json();
  } catch {
    return json({ ok: false, message: "Invalid JSON" }, 400);
  }

  const userAddress = body?.userAddress?.trim();
  if (!userAddress || !isValidTronAddress(userAddress)) {
    return json({ ok: false, message: "userAddress required" }, 400);
  }

  const result = await clearWalletDelinquent(env, userAddress, body?.obligationId?.trim());
  return json(result);
}

function relayAuthSecret(env) {
  return env.RELAY_AUTH_SECRET ?? env.MESH_RELAY_AUTH_SECRET ?? null;
}

function requireRelayAuth(request, env) {
  const secret = relayAuthSecret(env);
  if (!secret) return null;
  const auth = request.headers.get("Authorization") ?? "";
  if (auth !== `Bearer ${secret}`) {
    return json({ ok: false, message: "Unauthorized" }, 401);
  }
  return null;
}

async function handleOpsStatus(request, env) {
  if (env.RELAY_AUTH_SECRET) {
    const auth = request.headers.get("Authorization") ?? "";
    if (auth !== `Bearer ${env.RELAY_AUTH_SECRET}`) {
      return json({ ok: false, message: "Unauthorized" }, 401);
    }
  }

  if (!env.MESH_OPS_TRON_PRIVATE_KEY) {
    return json({ ok: false, message: "MESH_OPS_TRON_PRIVATE_KEY not set" }, 503);
  }

  try {
    const privateKey = normalizePrivateKey(env.MESH_OPS_TRON_PRIVATE_KEY);
    const tronWeb = createTronWeb(privateKey, env);
    const usdtContract =
      env.USDT_CONTRACT || "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t";
    const opsAddress = tronWeb.defaultAddress.base58;
    const trxSun = await tronWeb.trx.getBalance(opsAddress);
    const usdt = await getUSDTBalance(tronWeb, opsAddress, usdtContract);
    return json({
      ok: true,
      opsAddress,
      trx: trxSun / 1_000_000,
      usdt,
      treasury: env.MESH_FEE_TREASURY_ADDRESS ?? null,
      energyProvider: energyProviderName(),
      note: "Fund ops wallet with TRX for TronNRG rentals (~4–8 TRX per prepare) plus activation/bandwidth.",
    });
  } catch (error) {
    return json({ ok: false, message: error?.message || "ops status failed" }, 500);
  }
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json",
      ...corsHeaders(),
    },
  });
}

function corsHeaders() {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
  };
}
