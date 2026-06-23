import { fetchSupply, rentEnergy } from "./tronnrg.js";
import { trxAmountForTransfer, probeAccountEnergy } from "./tron.js";

export const STANDARD_ENERGY_TARGET = 65_000;
export const HIGH_ENERGY_TARGET = 130_000;

export function energyProviderName() {
  return "tronnrg";
}

export function energyTargetForTransfer({ highEnergy = false, hasUsdtOnRecipient = false } = {}) {
  if (highEnergy) {
    return HIGH_ENERGY_TARGET;
  }
  return hasUsdtOnRecipient ? STANDARD_ENERGY_TARGET : HIGH_ENERGY_TARGET;
}

/** Minimum on-chain Energy before renting again (matches iOS + send queue). */
export function prepareEnergyMinimum({ highEnergy = false } = {}) {
  return highEnergy ? 55_000 : 28_000;
}

/**
 * Provide Tron Energy for a sender before USDT broadcast (TronNRG rental).
 */
export async function provideEnergy({
  tronWeb,
  delegateTo,
  highEnergy = false,
  hasUsdtOnRecipient = false,
  env,
}) {
  const target = energyTargetForTransfer({ highEnergy, hasUsdtOnRecipient });
  const apiBase = env.TRONNRG_API_BASE || "https://api.tronnrg.com";
  const supply = await fetchSupply(apiBase);
  const trxAmount = highEnergy
    ? Math.max(supply?.examples?.new_wallet?.trx ?? 8, supply?.min_order_trx ?? 4)
    : trxAmountForTransfer(hasUsdtOnRecipient, supply);

  const result = await rentEnergy({
    tronWeb,
    delegateTo,
    trxAmount,
    apiBase,
    supply,
  });

  return {
    source: "tronnrg",
    energy: result.energy,
    energyTarget: target,
    delegationTx: result.delegationTx,
    paymentTx: result.txHash,
    trxPaid: trxAmount,
    tronnrgRef: result.ref,
    skipped: false,
  };
}

/**
 * Rent TronNRG only when the sender does not already have enough Energy.
 */
export async function ensureEnergyForSender({
  tronWeb,
  delegateTo,
  highEnergy = false,
  hasUsdtOnRecipient = false,
  env,
  minimumEnergy,
}) {
  const energyMinimum = minimumEnergy ?? prepareEnergyMinimum({ highEnergy });
  const currentEnergy = await probeAccountEnergy(tronWeb, delegateTo);
  if (currentEnergy >= energyMinimum) {
    return {
      source: "tronnrg",
      energy: currentEnergy,
      energyTarget: energyTargetForTransfer({ highEnergy, hasUsdtOnRecipient }),
      delegationTx: null,
      paymentTx: null,
      trxPaid: 0,
      tronnrgRef: null,
      skipped: true,
    };
  }

  return provideEnergy({
    tronWeb,
    delegateTo,
    highEnergy,
    hasUsdtOnRecipient,
    env,
  });
}

/** Liquid TRX needed on ops for TronNRG rental + activation/bandwidth. */
export function estimatePrepareLiquidTrxSun({
  activationCostSun,
  bandwidthCostSun,
  highEnergy = false,
  hasUsdtOnRecipient = false,
  skipEnergyRent = false,
}) {
  const minTrx = skipEnergyRent ? 0 : highEnergy ? 8 : hasUsdtOnRecipient ? 4 : 8;
  return minTrx * 1_000_000 + activationCostSun + bandwidthCostSun + 500_000;
}
