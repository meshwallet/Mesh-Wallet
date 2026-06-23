import { BackgroundSendService } from '@/services/background-send-service';
import { PendingSendStore } from '@/services/pending-send-store';
import { continueQueuedSend, fetchSendStatus } from '@/services/mesh/relay-http';
import { TronAPI, addressesMatch } from '@/services/tron/tron-api';
import type { PendingSendRecord } from '@/core/types';

const DIRECT_SEND_NO_TX_FAIL_AFTER_MS = 90_000;
const DIRECT_WORKER_UNREACHABLE_FAIL_AFTER_MS = 5 * 60_000;
const WORKER_EPHEMERAL_RETRY_AFTER_MS = 45_000;
const WORKER_HANDOFF_RETRY_GRACE_MS = 5 * 60_000;
const STATUS_POLL_STALE_MS = 8 * 60_000;
const PENDING_STATUS_FAIL_AFTER_MS = 3 * 60_000;
const EXPIRED_RESIGN_FAIL_AFTER_MS = 12 * 60_000;

const ABANDONED_SEND_MESSAGE =
  'Send did not finish in time. If your USDT balance is unchanged, you can try again.';
const WORKER_UNREACHABLE_MESSAGE =
  'Mesh could not confirm this send. Check your USDT balance — if funds are still there, try again.';
const WORKER_START_FAIL_MESSAGE =
  'Mesh could not start this send. Check your USDT balance and try again.';

function isPlausibleTronTransactionID(txID: string): boolean {
  const hex = txID.trim().toLowerCase();
  return hex.length === 64 && /^[0-9a-f]+$/.test(hex);
}

function isPermanentWorkerError(error: string): boolean {
  const lower = error.toLowerCase();
  return lower.includes('mismatch')
    || lower.includes('missing signature')
    || lower.includes('not a usdt')
    || lower.includes('not a transfer')
    || lower.includes('expired');
}

function isTransientWorkerError(error: string): boolean {
  if (!error) return true;
  if (isPermanentWorkerError(error)) return false;
  const lower = error.toLowerCase();
  return lower.includes('activate')
    || lower.includes('not exist')
    || lower.includes('does not exist')
    || lower.includes('energy')
    || lower.includes('not ready')
    || lower.includes('bandwidth')
    || lower.includes('timeout')
    || lower.includes('busy')
    || lower.includes('http');
}

function workerNetworkStarted(status: {
  mainTxID?: string;
  status?: string;
  networkStartedAtMs?: number;
  isPrivateSend?: boolean;
  currentStepIndex?: number;
  lastStepTxID?: string;
}): boolean {
  if (status.mainTxID) return true;
  switch (status.status) {
    case 'send_confirmed_fee_pending':
    case 'settled':
      return true;
    case 'processing_queue':
    case 'queued':
      return status.networkStartedAtMs != null;
    default:
      return false;
  }
}

function shouldSurfaceWorkerFailure(
  lastError: string | undefined,
  ageMs: number,
  queueAttempts = 0,
  maxGraceMs = WORKER_HANDOFF_RETRY_GRACE_MS,
): boolean {
  const error = lastError ?? '';
  if (isPermanentWorkerError(error)) return true;
  if (ageMs < maxGraceMs && isTransientWorkerError(error)) return false;
  if (queueAttempts >= 8) return true;
  if (ageMs >= STATUS_POLL_STALE_MS && queueAttempts >= 2) return true;
  return false;
}

async function workerNetworkGiveUpAfterMs(fromAddress: string): Promise<number> {
  const from = fromAddress.trim();
  if (!from) return WORKER_HANDOFF_RETRY_GRACE_MS;
  if (await TronAPI.isAccountActivated(from)) {
    return DIRECT_SEND_NO_TX_FAIL_AFTER_MS;
  }
  return WORKER_HANDOFF_RETRY_GRACE_MS;
}

function chainMatch(record: PendingSendRecord, chain: Awaited<ReturnType<typeof TronAPI.fetchTransactions>>) {
  const tolerance = 0.000001;
  const notBefore = new Date(record.startedAt).getTime() - 5000;
  const spendFrom = record.fromAddress.trim();
  const recipient = record.recipientAddress.trim();
  const pendingTxID = record.txID.trim();

  const matchesTransfer = (tx: (typeof chain)[number]) => {
    if (tx.direction !== 'outgoing') return false;
    if (!addressesMatch(tx.fromAddress, spendFrom)) return false;
    if (!addressesMatch(tx.toAddress, recipient)) return false;
    const delta = tx.amount - record.amountUSDT;
    if (delta < -tolerance || delta > tolerance) return false;
    return tx.timestamp.getTime() >= notBefore;
  };

  if (isPlausibleTronTransactionID(pendingTxID)) {
    const byID = chain.find((tx) => tx.txID === pendingTxID);
    return byID && matchesTransfer(byID) ? byID : null;
  }

  if (!spendFrom) return null;
  return chain.find(matchesTransfer) ?? null;
}

async function findChainMatch(record: PendingSendRecord) {
  const chain = await TronAPI.fetchTransactions(record.fromAddress, 80);
  return chainMatch(record, chain);
}

function markConfirmed(record: PendingSendRecord, txID?: string) {
  record.status = 'confirmed';
  record.stepMessage = 'Confirmed';
  if (txID) record.txID = txID;
}

function markFailed(record: PendingSendRecord, message: string) {
  record.status = 'failed';
  record.failedMessage = message;
}

export const SendPollService = {
  async pollPendingSends(): Promise<void> {
    const records = await PendingSendStore.getAll();
    const processing = records.filter((record) => record.status === 'processing');

    for (const record of processing) {
      const ageMs = Date.now() - new Date(record.startedAt).getTime();
      const giveUpAfterMs = await workerNetworkGiveUpAfterMs(record.fromAddress);

      const matched = await findChainMatch(record);
      if (matched) {
        markConfirmed(record, matched.txID);
        await PendingSendStore.upsert(record);
        continue;
      }

      const status = await fetchSendStatus(record.id);

      if (!status) {
        if (
          record.handoffRegistered
          && !record.isPrivateSendMode
          && ageMs > WORKER_EPHEMERAL_RETRY_AFTER_MS
        ) {
          await continueQueuedSend(record.id, record.handoffResumeJSON).catch(() => {});
          record.stepMessage = 'Mesh is processing your send…';
        }
        if (ageMs >= DIRECT_WORKER_UNREACHABLE_FAIL_AFTER_MS) {
          markFailed(record, WORKER_UNREACHABLE_MESSAGE);
        }
        await PendingSendStore.upsert(record);
        continue;
      }

      if (
        status.status === 'expired_needs_resign'
        || status.lastError?.includes('EXPIRED_NEEDS_RESIGN')
      ) {
        if (ageMs >= EXPIRED_RESIGN_FAIL_AFTER_MS) {
          markFailed(record, 'Send signature expired. Please try again.');
        }
        await PendingSendStore.upsert(record);
        continue;
      }

      if (status.mainTxID && !record.txID) {
        record.txID = status.mainTxID;
      }

      if (status.status === 'failed' && status.lastError?.trim()) {
        if (shouldSurfaceWorkerFailure(status.lastError, ageMs, status.queueAttempts, giveUpAfterMs)) {
          markFailed(record, status.lastError);
        } else if (record.handoffRegistered) {
          await continueQueuedSend(record.id, record.handoffResumeJSON).catch(() => {});
          record.stepMessage = 'Mesh is processing your send…';
        }
        await PendingSendStore.upsert(record);
        continue;
      }

      if (record.handoffRegistered) {
        if (workerNetworkStarted(status)) {
          if (!record.workerQueued) {
            record.workerQueued = true;
            record.stepMessage = 'Processing';
          }
        } else if (
          ageMs >= giveUpAfterMs
          && status.status === 'queued'
          && (status.currentStepIndex ?? 0) === 0
          && status.networkStartedAtMs == null
        ) {
          await continueQueuedSend(record.id, record.handoffResumeJSON).catch(() => {});
          markFailed(record, WORKER_START_FAIL_MESSAGE);
          await PendingSendStore.upsert(record);
          continue;
        } else if (ageMs > WORKER_EPHEMERAL_RETRY_AFTER_MS) {
          await continueQueuedSend(record.id, record.handoffResumeJSON).catch(() => {});
        }
      } else if (
        ageMs >= DIRECT_SEND_NO_TX_FAIL_AFTER_MS
        && !BackgroundSendService.isHandoffRunning()
        && record.id !== BackgroundSendService.getActiveSendID()
      ) {
        markFailed(record, ABANDONED_SEND_MESSAGE);
        await PendingSendStore.upsert(record);
        BackgroundSendService.syncFromStore(record);
        continue;
      }

      if (!record.workerQueued && !workerNetworkStarted(status)) {
        record.stepMessage = record.handoffRegistered
          ? 'Processing on Mesh…'
          : 'Preparing your send…';
        await PendingSendStore.upsert(record);
        continue;
      }

      switch (status.status) {
        case 'settled':
        case 'send_confirmed_fee_pending':
          if (status.mainTxID && isPlausibleTronTransactionID(status.mainTxID)) {
            markConfirmed(record, status.mainTxID);
          } else {
            record.stepMessage = 'Sending on network…';
          }
          break;
        case 'failed':
          if (shouldSurfaceWorkerFailure(status.lastError, ageMs, status.queueAttempts, giveUpAfterMs)) {
            markFailed(record, status.lastError ?? 'Send failed on the network. Please try again.');
          } else {
            record.stepMessage = 'Mesh is retrying on network…';
          }
          break;
        case 'pending':
          if (ageMs >= PENDING_STATUS_FAIL_AFTER_MS) {
            markFailed(
              record,
              'Send did not reach Mesh network. Check your USDT balance and try again.',
            );
          }
          break;
        case 'processing_queue':
        case 'queued':
          record.stepMessage = workerNetworkStarted(status)
            ? 'Sending on network…'
            : 'Processing on Mesh…';
          break;
        default:
          record.stepMessage = workerNetworkStarted(status)
            ? 'Sending on network…'
            : 'Processing on Mesh…';
          break;
      }

      if (
        record.status === 'processing'
        && ageMs >= giveUpAfterMs
        && !status.mainTxID
        && !(await findChainMatch(record))
      ) {
        markFailed(record, ABANDONED_SEND_MESSAGE);
      }

      await PendingSendStore.upsert(record);
      BackgroundSendService.syncFromStore(record);
    }
  },
};
