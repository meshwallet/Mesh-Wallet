import { CONFIG } from '@/core/config';
import type { DeepRecoveryState } from '@/core/types';
import { PrivacyService } from './privacy-service';

type ProgressCallback = (state: Partial<DeepRecoveryState>) => void;

let state: DeepRecoveryState = {
  isRunning: false,
  progressChecked: 0,
  progressTotal: CONFIG.deepRecoveryScanCount,
  isTransferring: false,
  statusMessage: null,
  errorMessage: null,
};

const listeners = new Set<(s: DeepRecoveryState) => void>();

function emit(partial: Partial<DeepRecoveryState>) {
  state = { ...state, ...partial };
  listeners.forEach((l) => l(state));
}

export const DeepRecoveryService = {
  getState: () => state,

  subscribe(cb: (s: DeepRecoveryState) => void) {
    listeners.add(cb);
    cb(state);
    return () => listeners.delete(cb);
  },

  async start(walletId?: string, onProgress?: ProgressCallback) {
    if (state.isRunning) return;
    emit({
      isRunning: true,
      progressChecked: 0,
      progressTotal: CONFIG.deepRecoveryScanCount,
      isTransferring: false,
      statusMessage: null,
      errorMessage: null,
    });

    try {
      const count = await PrivacyService.recoverDeepFundsToMainWallet(walletId, (progress) => {
        if (progress.phase === 'scanning') {
          emit({
            progressChecked: progress.checked,
            progressTotal: progress.total,
            isTransferring: false,
          });
        } else {
          emit({
            progressChecked: progress.current,
            progressTotal: progress.total,
            isTransferring: true,
          });
        }
        onProgress?.(state);
      });
      emit({
        isRunning: false,
        statusMessage: `Recovered funds from ${count} address(es).`,
        errorMessage: null,
      });
    } catch (e) {
      const msg = e instanceof Error ? e.message : 'Deep recovery failed';
      emit({ isRunning: false, errorMessage: msg, statusMessage: null });
      throw e;
    }
  },

  cancel() {
    emit({ isRunning: false, isTransferring: false });
  },
};
