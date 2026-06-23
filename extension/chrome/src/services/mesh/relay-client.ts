import type { SendHandoffResult } from '@/core/types';
import { collectsSendFee } from '@/core/config';
import { continueQueuedSend, fetchSendStatus, relayFetch } from '@/services/mesh/relay-http';

export { EnergyBroker } from '@/services/mesh/energy-broker';

export const MeshRelay = {
  isConfigured: true,

  async activateAddress(address: string): Promise<void> {
    await relayFetch('/v1/activate', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ address }),
    });
  },

  async prepareSender(params: {
    address: string;
    toAddress: string;
    highEnergy?: boolean;
    skipRecipientActivation?: boolean;
  }): Promise<void> {
    await relayFetch('/v1/prepare-sender', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        address: params.address,
        toAddress: params.toAddress,
        highEnergy: params.highEnergy ?? false,
        skipRecipientActivation: params.skipRecipientActivation ?? true,
      }),
    });
  },

  async registerQueuedSend(params: {
    handoff: SendHandoffResult;
    userAddress: string;
    recipientAddress: string;
    amountUSDT: number;
    feeUSDT: number;
    startedAt: Date;
  }): Promise<{ queued: boolean; mainTxID?: string; status?: string }> {
    const body = buildRegisterBody(params);

    const result = await relayFetch<{
      ok: boolean;
      queued?: boolean;
      mainTxID?: string;
      status?: string;
      message?: string;
    }>('/v1/register-send-fee', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });

    if (!result.ok) {
      throw new Error(result.message ?? 'Send registration failed');
    }

    return {
      queued: result.queued ?? false,
      mainTxID: result.mainTxID,
      status: result.status,
    };
  },

  fetchSendStatus,

  continueQueuedSend,

  async walletFeeStatus(address: string): Promise<{ delinquent: boolean }> {
    try {
      const result = await relayFetch<{ delinquent?: boolean }>(
        `/v1/wallet-fee-status?address=${encodeURIComponent(address)}`,
      );
      return { delinquent: result.delinquent ?? false };
    } catch {
      return { delinquent: false };
    }
  },

  encodeHandoffResumeJSON(params: {
    handoff: SendHandoffResult;
    userAddress: string;
    recipientAddress: string;
    amountUSDT: number;
    feeUSDT: number;
    startedAt: Date;
  }): string {
    return JSON.stringify(buildRegisterBody(params));
  },
};

function buildRegisterBody(params: {
  handoff: SendHandoffResult;
  userAddress: string;
  recipientAddress: string;
  amountUSDT: number;
  feeUSDT: number;
  startedAt: Date;
}): Record<string, unknown> {
  const body: Record<string, unknown> = {
    id: params.handoff.obligationID,
    userAddress: params.userAddress,
    recipientAddress: params.recipientAddress,
    amountUSDT: params.amountUSDT,
    feeUSDT: params.feeUSDT,
    highEnergy: params.handoff.highEnergy,
    isPrivateSend: params.handoff.isPrivateSend,
    sendMode: params.handoff.sendMode,
    startedAtMs: params.startedAt.getTime(),
  };

  if (params.handoff.signedMainTxJSON) {
    body.signedMainTxJSON = params.handoff.signedMainTxJSON;
  }
  if (params.handoff.signedMainTxSteps?.length) {
    body.signedMainTxSteps = params.handoff.signedMainTxSteps;
  }
  if (!collectsSendFee(params.handoff.isPrivateSend)) {
    body.userFeeWaived = true;
  }
  return body;
}
