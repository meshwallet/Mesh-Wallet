import { TronWeb } from "tronweb";

const USDT_DECIMALS = 6;

export function normalizePrivateKey(raw) {
  const trimmed = (raw ?? "").trim().replace(/^0x/i, "");
  if (!/^[0-9a-fA-F]{64}$/.test(trimmed)) {
    throw new Error("MESH_OPS_TRON_PRIVATE_KEY must be 64 hex characters");
  }
  return trimmed;
}

export function createTronWeb(privateKeyHex, env) {
  const headers = {};
  if (env.TRONGRID_API_KEY) {
    headers["TRON-PRO-API-KEY"] = env.TRONGRID_API_KEY;
  }

  return new TronWeb({
    fullHost: env.TRONGRID_HOST || "https://api.trongrid.io",
    headers,
    privateKey: privateKeyHex,
  });
}

export function isValidTronAddress(address) {
  return TronWeb.isAddress(address);
}

/**
 * Returns true if address holds any USDT (cheaper 65k energy on TronNRG).
 */
export async function recipientHasUSDT(tronWeb, address, contractAddress) {
  try {
    const contract = await tronWeb.contract().at(contractAddress);
    const raw = await contract.balanceOf(address).call();
    const balance = Number(raw?.toString?.() ?? raw ?? 0);
    return balance > 0;
  } catch (error) {
    console.warn("USDT balance check failed, using new-wallet energy tier", error);
    return false;
  }
}

export function trxAmountForTransfer(hasUsdtOnRecipient, supply) {
  const minTrx = supply?.min_order_trx ?? 4;
  const examples = supply?.examples ?? {};
  const standard = examples.standard?.trx ?? minTrx;
  const newWallet = examples.new_wallet?.trx ?? 8;
  return hasUsdtOnRecipient ? Math.max(standard, minTrx) : Math.max(newWallet, minTrx);
}

/** 1 TRX — minimum to create an account on Tron. */
export const ACTIVATION_TRX_SUN = 1_000_000;

export async function isAccountActivated(tronWeb, address) {
  try {
    const account = await tronWeb.trx.getAccount(address);
    const createTime = Number(account?.create_time ?? 0);
    if (createTime > 0) {
      return true;
    }
    const balance = Number(account?.balance ?? 0);
    return balance >= ACTIVATION_TRX_SUN;
  } catch (error) {
    console.warn("activation check failed", address, error);
    return false;
  }
}

/** True when Mesh should send 1 TRX to activate an address (sender / relay / receive slot only). */
export async function needsActivation(tronWeb, address, _usdtContract) {
  return !(await isAccountActivated(tronWeb, address));
}

/** One short wait + single lookup (keeps Worker subrequests low). */
export async function briefWaitForTx(tronWeb, txHash, waitMs = 8_000) {
  if (!txHash) {
    return;
  }
  await sleep(waitMs);
  try {
    const info = await tronWeb.trx.getTransactionInfo(txHash);
    if (info?.blockNumber || info?.receipt?.result === "SUCCESS") {
      return;
    }
  } catch {
    // Non-fatal — iOS polls account state before broadcast.
  }
}

export async function waitForTransactionConfirmation(tronWeb, txHash, timeoutMs = 60_000) {
  const deadline = Date.now() + timeoutMs;
  let checks = 0;
  const maxChecks = Math.min(8, Math.ceil(timeoutMs / 4000));

  while (Date.now() < deadline && checks < maxChecks) {
    checks += 1;
    try {
      const info = await tronWeb.trx.getTransactionInfo(txHash);
      if (info?.blockNumber || info?.receipt?.result === "SUCCESS") {
        return;
      }
    } catch {
      // still pending
    }
    await sleep(4000);
  }
  throw new Error(`Transaction ${txHash} was not confirmed in time`);
}

/**
 * Poll activation with a fixed check budget (Cloudflare Worker subrequest limit).
 */
export async function waitForAccountActivated(
  tronWeb,
  address,
  maxChecks = 10,
  intervalMs = 3_500
) {
  for (let i = 0; i < maxChecks; i += 1) {
    if (await isAccountActivated(tronWeb, address)) {
      return true;
    }
    if (i < maxChecks - 1) {
      await sleep(intervalMs);
    }
  }
  return false;
}

/**
 * Sends 1 TRX from the ops wallet when `address` has never been activated.
 * Returns the activation tx hash, or null if already active.
 */
export async function ensureAccountActivated(
  tronWeb,
  address,
  { maxChecks = 10, intervalMs = 3_500 } = {}
) {
  if (await isAccountActivated(tronWeb, address)) {
    return null;
  }

  const payment = await tronWeb.trx.sendTransaction(address, ACTIVATION_TRX_SUN);
  const txHash = payment?.txid ?? payment?.transaction?.txID ?? payment?.txID;
  if (!txHash) {
    throw new Error(`Failed to activate Tron address ${address}`);
  }

  await briefWaitForTx(tronWeb, txHash, 6_000);
  if (await waitForAccountActivated(tronWeb, address, maxChecks, intervalMs)) {
    return txHash;
  }
  throw new Error(`Tron address ${address} did not activate in time`);
}

export async function getUSDTBalance(tronWeb, address, contractAddress) {
  try {
    const contract = await tronWeb.contract().at(contractAddress);
    const raw = await contract.balanceOf(address).call();
    return Number(raw?.toString?.() ?? raw ?? 0) / 1_000_000;
  } catch (error) {
    console.warn("USDT balance check failed", address, error);
    return 0;
  }
}

export async function transferUSDT(tronWeb, toAddress, amountUSDT, contractAddress) {
  const contract = await tronWeb.contract().at(contractAddress);
  const amountSun = Math.round(amountUSDT * 1_000_000);
  if (amountSun <= 0) {
    throw new Error("USDT amount must be positive");
  }
  const receipt = await contract.transfer(toAddress, amountSun).send({
    feeLimit: 150_000_000,
  });
  const txid =
    typeof receipt === "string"
      ? receipt
      : receipt?.txid ?? receipt?.transaction?.txID ?? receipt?.txID;
  if (!txid) {
    throw new Error("USDT transfer did not return a transaction id");
  }
  return txid;
}

const MIN_BANDWIDTH_FOR_TRC20 = 400;
/** TRX sent from ops when sender has no free bandwidth and almost no TRX to burn. */
export const BANDWIDTH_TOPUP_TRX_SUN = 3_000_000;

export async function getAvailableBandwidth(tronWeb, address) {
  try {
    const resources = await tronWeb.trx.getAccountResources(address);
    const freeNet = Number(resources?.freeNetLimit ?? 0) - Number(resources?.freeNetUsed ?? 0);
    const net = Number(resources?.NetLimit ?? 0) - Number(resources?.NetUsed ?? 0);
    return Math.max(0, freeNet, net);
  } catch (error) {
    console.warn("getAccountResources bandwidth failed", address, error);
    return 0;
  }
}

/**
 * Sends TRX from ops so the sender can pay bandwidth if free quota is exhausted.
 * Returns tx hash or null if already sufficient.
 */
export async function ensureSenderBandwidth(tronWeb, address) {
  let lastTxHash = null;

  for (let attempt = 0; attempt < 3; attempt += 1) {
    const bandwidth = await getAvailableBandwidth(tronWeb, address);
    const balanceSun = await tronWeb.trx.getBalance(address);
    if (bandwidth >= MIN_BANDWIDTH_FOR_TRC20 || balanceSun >= BANDWIDTH_TOPUP_TRX_SUN) {
      return lastTxHash;
    }

    const payment = await tronWeb.trx.sendTransaction(address, BANDWIDTH_TOPUP_TRX_SUN);
    const txHash = payment?.txid ?? payment?.transaction?.txID ?? payment?.txID;
    if (!txHash) {
      throw new Error(`Failed to fund bandwidth TRX for ${address}`);
    }
    lastTxHash = txHash;
    await waitForTransactionConfirmation(tronWeb, txHash, 25_000);
  }

  const finalBandwidth = await getAvailableBandwidth(tronWeb, address);
  const finalBalanceSun = await tronWeb.trx.getBalance(address);
  if (finalBandwidth >= MIN_BANDWIDTH_FOR_TRC20 || finalBalanceSun >= BANDWIDTH_TOPUP_TRX_SUN) {
    return lastTxHash;
  }

  throw new Error(
    `Sender bandwidth/TRX still insufficient for ${address} (bandwidth ${finalBandwidth}, trx ${(finalBalanceSun / 1e6).toFixed(2)})`
  );
}

/** Idempotent bandwidth top-up used by the send queue (at most one top-up per send step). */
export async function ensureSenderBandwidthOnce(tronWeb, address, _env) {
  return ensureSenderBandwidth(tronWeb, address);
}

const TRANSFER_TOPIC =
  "ddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef";

function topicAddress(topic) {
  const hex = String(topic ?? "").replace(/^0x/i, "").toLowerCase();
  return hex.length >= 40 ? hex.slice(-40) : "";
}

/** Confirms a router send-with-fee tx credited the Mesh treasury. */
export async function verifyRouterSendFee(tronWeb, txID, env, expectedFee) {
  const treasury = env.MESH_FEE_TREASURY_ADDRESS?.trim();
  if (!treasury || !(Number(expectedFee) > 0)) {
    return true;
  }

  try {
    const info = await tronWeb.trx.getTransactionInfo(txID);
    if (info?.receipt?.result && info.receipt.result !== "SUCCESS") {
      return false;
    }

    const treasuryTopic = topicAddress(tronWeb.address.toHex(treasury));
    const expectedSun = Math.round(Number(expectedFee) * 1_000_000);
    const tolerance = Math.max(1, Math.round(expectedSun * 0.001));

    for (const log of info?.log ?? []) {
      if (String(log?.topics?.[0] ?? "").toLowerCase() !== TRANSFER_TOPIC) {
        continue;
      }
      if (topicAddress(log?.topics?.[2]) !== treasuryTopic) {
        continue;
      }
      const raw = BigInt(`0x${String(log?.data ?? "0").replace(/^0x/i, "") || "0"}`);
      if (Number(raw) + tolerance >= expectedSun) {
        return true;
      }
    }
    return false;
  } catch (error) {
    console.warn("verifyRouterSendFee failed", txID, error);
    return false;
  }
}

export async function getAvailableEnergy(tronWeb, address) {
  try {
    const resources = await tronWeb.trx.getAccountResources(address);
    const limit = Number(resources?.EnergyLimit ?? 0);
    const used = Number(resources?.EnergyUsed ?? 0);
    return Math.max(0, limit - used);
  } catch (error) {
    console.warn("getAccountResources failed", address, error);
    return 0;
  }
}

/** Quick energy probe (full polling runs on iOS to avoid Worker subrequest limits). */
export async function probeAccountEnergy(tronWeb, address) {
  return getAvailableEnergy(tronWeb, address);
}

/** Broadcast a signed transaction JSON (WalletCore / TronWeb format). */
export async function broadcastSignedTransaction(tronWeb, env, signedTxJSON) {
  let tx;
  try {
    tx = typeof signedTxJSON === "string" ? JSON.parse(signedTxJSON) : signedTxJSON;
  } catch {
    throw new Error("Invalid signed fee transaction JSON");
  }

  if (!Array.isArray(tx?.signature) || tx.signature.length === 0) {
    throw new Error("Signed fee transaction missing signature");
  }

  const expiration = Number(tx?.raw_data?.expiration ?? 0);
  if (expiration > 0 && Date.now() >= expiration) {
    throw new Error("Pre-signed fee transaction expired");
  }

  const host = (env.TRONGRID_HOST || "https://api.trongrid.io").replace(/\/$/, "");
  const headers = { "Content-Type": "application/json" };
  if (env.TRONGRID_API_KEY) {
    headers["TRON-PRO-API-KEY"] = env.TRONGRID_API_KEY;
  }

  const response = await fetch(`${host}/wallet/broadcasttransaction`, {
    method: "POST",
    headers,
    body: JSON.stringify(tx),
  });
  const result = await response.json().catch(() => ({}));
  if (result?.result !== true) {
    const reason = result?.message ?? result?.code ?? `broadcast HTTP ${response.status}`;
    throw new Error(reason);
  }

  const txID = result?.txid ?? result?.txID ?? tx?.txID;
  if (!txID) {
    throw new Error("Fee broadcast did not return txid");
  }
  return txID;
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
