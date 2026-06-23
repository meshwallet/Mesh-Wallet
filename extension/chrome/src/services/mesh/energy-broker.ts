import { TronAPI } from '@/services/tron/tron-api';
import { MeshRelay } from '@/services/mesh/relay-client';

const PREFERRED_ENERGY = 65_000;
const HIGH_ENERGY_MIN = 130_000;
const MIN_BANDWIDTH = 400;
const MIN_TRX_FOR_BANDWIDTH = 2.8;

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function energyMinimum(highEnergy: boolean): number {
  return highEnergy ? HIGH_ENERGY_MIN : PREFERRED_ENERGY;
}

async function hasTransferEnergy(address: string, minimum: number): Promise<boolean> {
  const resources = await TronAPI.fetchAccountResources(address);
  return resources.energyRemaining >= minimum;
}

async function hasSufficientBandwidth(address: string): Promise<boolean> {
  const resources = await TronAPI.fetchAccountResources(address);
  return resources.bandwidthRemaining >= MIN_BANDWIDTH
    || resources.trxBalance >= MIN_TRX_FOR_BANDWIDTH;
}

export const EnergyBroker = {
  /** Activates a Mesh-owned address on Tron and waits for confirmation (iOS parity). */
  async ensureActivatedOnTron(
    address: string,
    onProgress?: (message: string) => void,
  ): Promise<void> {
    if (await TronAPI.isAccountActivated(address)) return;

    onProgress?.('Activating address on Tron…');
    let lastError: unknown;
    for (let attempt = 0; attempt < 8; attempt += 1) {
      try {
        await MeshRelay.activateAddress(address);
        lastError = undefined;
        break;
      } catch (error) {
        lastError = error;
        if (attempt >= 7) break;
        await sleep(2000 + attempt * 1000);
      }
    }
    if (lastError) throw lastError;

    onProgress?.('Waiting for activation confirmation…');
    const deadline = Date.now() + 120_000;
    while (Date.now() < deadline) {
      if (await TronAPI.isAccountActivated(address)) return;
      await sleep(2000);
    }

    if (!(await TronAPI.isAccountActivated(address))) {
      throw new Error('Activation is taking longer than expected. Please wait and try again.');
    }
  },

  /** Delegates energy/bandwidth via relay and polls until the sender can broadcast. */
  async ensureSenderReadyForBroadcast(
    address: string,
    toAddress: string,
    highEnergy = false,
    onProgress?: (message: string) => void,
  ): Promise<void> {
    const energyMin = energyMinimum(highEnergy);
    if (await hasTransferEnergy(address, energyMin) && await hasSufficientBandwidth(address)) {
      return;
    }

    onProgress?.('Preparing network…');
    const preparePromise = MeshRelay.prepareSender({
      address,
      toAddress,
      highEnergy,
      skipRecipientActivation: true,
    }).catch(() => {});

    const deadline = Date.now() + 90_000;
    let energyPrepareAttempts = 0;
    let lastEnergyPrepareAt = 0;

    while (Date.now() < deadline) {
      const resources = await TronAPI.fetchAccountResources(address);
      const energyReady = resources.energyRemaining >= energyMin;
      const bandwidthReady = resources.bandwidthRemaining >= MIN_BANDWIDTH
        || resources.trxBalance >= MIN_TRX_FOR_BANDWIDTH;

      if (energyReady && bandwidthReady) {
        await preparePromise;
        return;
      }

      const now = Date.now();
      if (energyPrepareAttempts < 12 && now - lastEnergyPrepareAt >= 3000) {
        onProgress?.(energyReady ? 'Preparing network bandwidth…' : 'Requesting network energy…');
        await MeshRelay.prepareSender({
          address,
          toAddress,
          highEnergy,
          skipRecipientActivation: true,
        }).catch(() => {});
        energyPrepareAttempts += 1;
        lastEnergyPrepareAt = now;
      }

      await sleep(500);
    }

    throw new Error('Network preparation timed out. Please try again.');
  },

  /** Used by consolidate and legacy call sites. */
  async ensureSenderReady(from: string, to: string, highEnergy = false): Promise<void> {
    await this.ensureActivatedOnTron(from);
    await this.ensureSenderReadyForBroadcast(from, to, highEnergy);
  },
};
