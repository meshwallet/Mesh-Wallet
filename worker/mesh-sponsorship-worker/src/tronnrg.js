const DEFAULT_API = "https://api.tronnrg.com";
const DELEGATE_RETRIES = 2;
const DELEGATE_RETRY_MS = 2500;
const POST_PAYMENT_MS = 6000;

export async function fetchSupply(apiBase) {
  const response = await fetch(`${apiBase}/supply`);
  if (!response.ok) {
    throw new Error(`TronNRG /supply HTTP ${response.status}`);
  }
  return response.json();
}

/**
 * Pay TRX → sign → POST /delegate. Returns TronNRG result object.
 */
export async function rentEnergy({
  tronWeb,
  delegateTo,
  trxAmount,
  apiBase = DEFAULT_API,
  supply: cachedSupply,
}) {
  const supply = cachedSupply ?? (await fetchSupply(apiBase));
  const payTo = supply.pay_to;
  if (!payTo) {
    throw new Error("TronNRG supply missing pay_to address");
  }

  const amountSun = Math.round(trxAmount * 1_000_000);
  if (amountSun < 4_000_000) {
    throw new Error("TronNRG minimum order is 4 TRX");
  }

  const payment = await tronWeb.trx.sendTransaction(payTo, amountSun);
  const txHash = payment?.txid ?? payment?.transaction?.txID ?? payment?.txID;
  if (!txHash) {
    throw new Error("TRX payment broadcast did not return txid");
  }

  await sleep(POST_PAYMENT_MS);

  const message = `${txHash}:${delegateTo}`;
  const signature = await tronWeb.trx.signMessageV2(message);

  let lastError = null;
  for (let attempt = 0; attempt < DELEGATE_RETRIES; attempt += 1) {
    const result = await postDelegate(apiBase, {
      tx_hash: txHash,
      delegate_to: delegateTo,
      signature,
    });

    if (!result.error) {
      return {
        txHash,
        energy: result.energy,
        cost: result.cost,
        ref: result.ref,
        delegationTx: result.delegations?.[0]?.tx ?? null,
      };
    }

    lastError = result;
    if (result.error === "hash_already_used") {
      throw new Error(`TronNRG: payment already claimed (${result.message})`);
    }
    if (result.error !== "payment_verification_failed") {
      throw new Error(result.message || result.error);
    }

    if (attempt < DELEGATE_RETRIES - 1) {
      await sleep(DELEGATE_RETRY_MS);
    }
  }

  throw new Error(
    lastError?.message ||
      "TronNRG could not verify TRX payment yet. Try again shortly."
  );
}

async function postDelegate(apiBase, body) {
  const response = await fetch(`${apiBase}/delegate`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });

  const data = await response.json().catch(() => ({}));
  if (!response.ok && !data.error) {
    return {
      error: "http_error",
      message: `TronNRG /delegate HTTP ${response.status}`,
    };
  }
  return data;
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
