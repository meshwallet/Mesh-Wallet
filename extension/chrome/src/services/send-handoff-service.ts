import type { PrivacySpendSource } from '@/core/types';
import type { SendHandoffResult } from '@/core/types';
import { CONFIG } from '@/core/config';
import { PrivacyService } from '@/services/mesh/privacy-service';
import { TronAPI } from '@/services/tron/tron-api';
import { WalletCredentials } from '@/services/tron/wallet-service';
import { TransactionService } from '@/services/tron/transaction-service';

/** Builds pre-signed direct sends for the worker queue (iOS: MeshSendHandoffService). */
export const SendHandoffService = {
  async performDirectHandoff(params: {
    walletId: string;
    obligationId: string;
    recipient: string;
    amount: number;
    slotIndex: number;
    spendSource?: PrivacySpendSource;
    onProgress?: (message: string) => void;
  }): Promise<SendHandoffResult> {
    if (!CONFIG.relayUrl?.trim()) {
      throw new Error(
        'Send service is temporarily unavailable. Please try again in a few minutes.',
      );
    }

    const source = params.spendSource ?? await (async () => {
      params.onProgress?.('Preparing your transfer…');
      return PrivacyService.resolveSpendSourceFromSlot(
        params.slotIndex,
        params.amount,
        params.walletId,
        { skipBalanceVerification: true },
      );
    })();

    params.onProgress?.('Signing transfer…');
    const recipientBalance = await TronAPI.fetchUSDTBalance(params.recipient);
    const highEnergy = (recipientBalance ?? 0) <= 0;

    const pk = await WalletCredentials.signingKey(source.derivationPath, params.walletId);
    const signed = await TransactionService.buildSignedUSDTTransaction({
      privateKeyHex: pk,
      fromAddress: source.address,
      toAddress: params.recipient,
      amount: params.amount,
      expirationOffsetMs: CONFIG.handoffExpirationMs,
    });

    params.onProgress?.('Sending to Mesh…');
    return {
      obligationID: params.obligationId,
      userAddress: source.address,
      signedMainTxJSON: signed.rawJSON,
      signedMainTxSteps: null,
      highEnergy,
      isPrivateSend: false,
      sendMode: 'direct',
    };
  },
};
