import { TronWeb } from 'tronweb';
import { CONFIG } from '@/core/config';
import { TronAPI } from './tron-api';

const tronWeb = new TronWeb({ fullHost: CONFIG.tronGridBase });

function usdtToSmallestUnits(amount: number): string {
  return Math.round(amount * 10 ** CONFIG.tokenDecimals).toString();
}

export interface SignedTxResult {
  txID: string;
  rawJSON: string;
  broadcastBody: object;
}

export const TransactionService = {
  async buildSignedUSDTTransaction(params: {
    privateKeyHex: string;
    fromAddress: string;
    toAddress: string;
    amount: number;
    expirationOffsetMs?: number;
  }): Promise<SignedTxResult> {
    const amountSun = usdtToSmallestUnits(params.amount);
    const expirationOffsetMs = params.expirationOffsetMs ?? CONFIG.handoffExpirationMs;
    const block = await TronAPI.getLatestBlock();
    const expiration = block.timestamp + expirationOffsetMs;

    const built = await tronWeb.transactionBuilder.triggerSmartContract(
      CONFIG.usdtContract,
      'transfer(address,uint256)',
      {
        feeLimit: CONFIG.defaultFeeLimit,
        blockHeader: {
          timestamp: block.timestamp,
          ref_block_bytes: block.refBlockBytes,
          ref_block_hash: block.refBlockHash,
          expiration,
        },
      },
      [
        { type: 'address', value: params.toAddress },
        { type: 'uint256', value: amountSun },
      ],
      params.fromAddress,
    );

    if (!built.result?.result) {
      throw new Error('Failed to build USDT transaction');
    }

    const signed = await tronWeb.trx.sign(
      built.transaction,
      params.privateKeyHex,
    );

    const txID = signed.txID ?? '';
    const rawJSON = JSON.stringify(signed);
    return { txID, rawJSON, broadcastBody: signed };
  },

  async sendUSDT(params: {
    privateKeyHex: string;
    fromAddress: string;
    toAddress: string;
    amount: number;
    skipPrepare?: boolean;
    onStatus?: (msg: string) => void;
  }): Promise<{ txID: string; rawJSON: string }> {
    if (!params.skipPrepare) {
      params.onStatus?.('Preparing network…');
    }

    const signed = await this.buildSignedUSDTTransaction({
      privateKeyHex: params.privateKeyHex,
      fromAddress: params.fromAddress,
      toAddress: params.toAddress,
      amount: params.amount,
    });

    params.onStatus?.('Broadcasting…');
    const txID = await TronAPI.broadcastTransaction(signed.broadcastBody);
    return { txID, rawJSON: signed.rawJSON };
  },

  async broadcastSigned(rawJSON: string): Promise<string> {
    const body = JSON.parse(rawJSON);
    return TronAPI.broadcastTransaction(body);
  },
};
