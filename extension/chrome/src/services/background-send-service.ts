import { v4 as uuidv4 } from 'uuid';
import { workerRegistrationFee } from '@/core/config';
import type { PendingSendRecord } from '@/core/types';
import { PendingSendStore } from '@/services/pending-send-store';
import { SendHandoffService } from '@/services/send-handoff-service';
import { MeshRelay } from '@/services/mesh/relay-client';
import { PrivacyService } from '@/services/mesh/privacy-service';
import { TronAPI } from '@/services/tron/tron-api';

export interface SendExecutionContext {
  walletId: string;
  recipient: string;
  amount: number;
  amountText: string;
  slotIndex: number;
}

/** iOS: MeshBackgroundSendService tracked state */
let trackedTransfers: PendingSendRecord[] = [];
let current: PendingSendRecord | null = null;
let activeSendID: string | null = null;
let handoffPinnedSendID: string | null = null;
let handoffPinnedWalletID: string | null = null;
const retainedContexts = new Map<string, SendExecutionContext>();
let handoffPromise: Promise<void> | null = null;
let isHandoffRunning = false;
let hydrated = false;

const AMOUNT_TOLERANCE = 0.000001;
const REUSABLE_CONFIRMED_WINDOW_MS = 30 * 60 * 1000;

function isPlausibleTronTransactionID(txID: string): boolean {
  const hex = txID.trim().toLowerCase();
  return hex.length === 64 && /^[0-9a-f]+$/.test(hex);
}

function upsertTracked(item: PendingSendRecord): void {
  const idx = trackedTransfers.findIndex((record) => record.id === item.id);
  if (idx >= 0) trackedTransfers[idx] = item;
  else trackedTransfers.unshift(item);
  if (current?.id === item.id) current = item;
}

async function persist(item: PendingSendRecord): Promise<void> {
  upsertTracked(item);
  await PendingSendStore.upsert(item);
}

async function ensureHydrated(): Promise<void> {
  if (hydrated) return;
  trackedTransfers = await PendingSendStore.getAll();
  const processing = trackedTransfers.find((item) => item.status === 'processing');
  if (processing) {
    current = processing;
    activeSendID = processing.id;
  }
  hydrated = true;
}

function isReusableInFlightTransfer(item: PendingSendRecord): boolean {
  if (item.status === 'processing') return true;
  if (item.status === 'confirmed') {
    return Date.now() - new Date(item.startedAt).getTime() < REUSABLE_CONFIRMED_WINDOW_MS;
  }
  return false;
}

function matchingInFlightTransfer(ctx: SendExecutionContext): PendingSendRecord | null {
  const recipient = ctx.recipient.trim().toLowerCase();
  return trackedTransfers
    .filter((item) => item.walletID === ctx.walletId && isReusableInFlightTransfer(item))
    .sort((a, b) => new Date(b.startedAt).getTime() - new Date(a.startedAt).getTime())
    .find((item) => {
      const delta = item.amountUSDT - ctx.amount;
      if (delta < -AMOUNT_TOLERANCE || delta > AMOUNT_TOLERANCE) return false;
      return item.recipientAddress.trim().toLowerCase() === recipient;
    }) ?? null;
}

function buildPendingTransfer(
  ctx: SendExecutionContext,
  stepMessage: string,
): PendingSendRecord {
  const existing = matchingInFlightTransfer(ctx);
  if (existing) {
    existing.stepMessage = stepMessage;
    return existing;
  }

  const startedAt = new Date().toISOString();
  return {
    id: uuidv4(),
    walletID: ctx.walletId,
    recipientAddress: ctx.recipient.trim(),
    amountText: ctx.amountText,
    amountUSDT: ctx.amount,
    isPrivateSendMode: false,
    selectedSendSlotIndex: ctx.slotIndex,
    stepMessage,
    startedAt,
    txID: '',
    fromAddress: '',
    toAddress: ctx.recipient.trim(),
    status: 'processing',
    handoffRegistered: false,
    workerQueued: false,
    handoffResumeJSON: undefined,
  };
}

function executionContextFromRecord(record: PendingSendRecord): SendExecutionContext {
  return {
    walletId: record.walletID,
    recipient: record.recipientAddress,
    amount: record.amountUSDT,
    amountText: record.amountText,
    slotIndex: record.selectedSendSlotIndex,
  };
}

async function attachChainUSDTAtStart(
  item: PendingSendRecord,
  ctx: SendExecutionContext,
): Promise<void> {
  if (item.chainUSDTAtStart != null) return;
  try {
    const source = await PrivacyService.resolveSpendSourceFromSlot(
      ctx.slotIndex,
      ctx.amount,
      ctx.walletId,
      { skipBalanceVerification: true },
    );
    const balance = await TronAPI.fetchUSDTBalance(source.address);
    if (balance != null) {
      item.chainUSDTAtStart = String(balance);
    }
  } catch {
    // Chain snapshot is best-effort; polling still works without it.
  }
}

function resolvePendingTransfer(id: string): PendingSendRecord | null {
  if (current?.id === id) return current;
  return trackedTransfers.find((item) => item.id === id) ?? null;
}

async function resolvePendingRecord(sendId: string): Promise<PendingSendRecord | null> {
  const local = resolvePendingTransfer(sendId);
  if (local) return local;

  await ensureHydrated();
  const tracked = trackedTransfers.find((item) => item.id === sendId);
  if (tracked) {
    if (activeSendID === sendId) current = tracked;
    return tracked;
  }

  const fromStore = (await PendingSendStore.getAll()).find((item) => item.id === sendId);
  if (!fromStore) return null;

  upsertTracked(fromStore);
  if (activeSendID === sendId) current = fromStore;
  return fromStore;
}

async function mutateTransfer(
  id: string,
  mutate: (record: PendingSendRecord) => void,
): Promise<PendingSendRecord | null> {
  let item = await resolvePendingRecord(id);
  if (!item) return null;
  mutate(item);
  await persist(item);
  return item;
}

function clearHandoffPins(): void {
  handoffPinnedSendID = null;
  handoffPinnedWalletID = null;
}

async function syncHandoffRegisteredFromWorker(obligationId: string): Promise<boolean> {
  const status = await MeshRelay.fetchSendStatus(obligationId);
  if (!status || status.hasSignedMain === false) return false;

  const accepted = new Set([
    'queued',
    'processing_queue',
    'send_confirmed_fee_pending',
    'settled',
  ]);
  if (!status.status || !accepted.has(status.status)) return false;

  await mutateTransfer(obligationId, (record) => {
    record.handoffRegistered = true;
  });
  return true;
}

function markHandoffFailed(id: string, message: string): void {
  void mutateTransfer(id, (record) => {
    record.status = 'failed';
    record.failedMessage = message;
    record.stepMessage = message;
  });
}

async function performHandoffWork(
  sendId: string,
  ctx: SendExecutionContext,
  onProgress?: (message: string) => void,
): Promise<void> {
  const pinnedID = handoffPinnedSendID ?? sendId;
  let record = await resolvePendingRecord(pinnedID);
  if (!record) {
    throw new Error('Send session was lost. Please try again.');
  }

  handoffPinnedSendID = pinnedID;
  handoffPinnedWalletID = record.walletID;
  activeSendID = pinnedID;
  current = record;
  retainedContexts.set(pinnedID, ctx);

  if (record.handoffRegistered) return;

  if (await syncHandoffRegisteredFromWorker(pinnedID)) {
    record = await resolvePendingRecord(pinnedID);
    if (record?.handoffRegistered) return;
  }

  onProgress?.('Preparing your transfer…');
  const source = await PrivacyService.resolveSpendSourceFromSlot(
    ctx.slotIndex,
    ctx.amount,
    ctx.walletId,
    { skipBalanceVerification: true },
  );

  await mutateTransfer(pinnedID, (pending) => {
    pending.fromAddress = source.address;
    if (pending.chainUSDTAtStart == null) {
      void TronAPI.fetchUSDTBalance(source.address).then((balance) => {
        if (balance == null) return;
        void mutateTransfer(pinnedID, (item) => {
          item.chainUSDTAtStart = String(balance);
        });
      });
    }
  });

  const handoff = await SendHandoffService.performDirectHandoff({
    walletId: ctx.walletId,
    obligationId: pinnedID,
    recipient: ctx.recipient,
    amount: ctx.amount,
    slotIndex: ctx.slotIndex,
    spendSource: source,
    onProgress: (message) => {
      void mutateTransfer(pinnedID, (pending) => {
        pending.stepMessage = message;
      });
      onProgress?.(message);
    },
  });

  const fee = workerRegistrationFee(false);
  const latest = await resolvePendingRecord(pinnedID);
  if (!latest) {
    throw new Error('Send session was lost. Please try again.');
  }

  const startedAt = new Date(latest.startedAt);
  const resumeJSON = MeshRelay.encodeHandoffResumeJSON({
    handoff,
    userAddress: handoff.userAddress,
    recipientAddress: ctx.recipient,
    amountUSDT: ctx.amount,
    feeUSDT: fee,
    startedAt,
  });

  await mutateTransfer(pinnedID, (pending) => {
    pending.fromAddress = handoff.userAddress;
    pending.handoffResumeJSON = resumeJSON;
    pending.stepMessage = 'Registering with Mesh…';
  });
  onProgress?.('Registering with Mesh…');

  const registerResult = await MeshRelay.registerQueuedSend({
    handoff,
    userAddress: handoff.userAddress,
    recipientAddress: ctx.recipient,
    amountUSDT: ctx.amount,
    feeUSDT: fee,
    startedAt,
  });

  if (!registerResult.queued && !registerResult.mainTxID) {
    throw new Error('Send service is outdated. Update Mesh relay, then try again.');
  }

  const mainTxID = registerResult.mainTxID?.trim() ?? '';
  if (mainTxID) {
    await mutateTransfer(pinnedID, (pending) => {
      pending.handoffRegistered = true;
      pending.workerQueued = true;
      pending.stepMessage = 'Processing on Mesh…';
      if (isPlausibleTronTransactionID(mainTxID)) {
        pending.txID = mainTxID;
      }
    });
  } else {
    await mutateTransfer(pinnedID, (pending) => {
      pending.handoffRegistered = true;
      pending.workerQueued = false;
      pending.stepMessage = 'Processing on Mesh…';
    });
  }

  chrome.runtime.sendMessage({ type: 'POLL_SENDS' }).catch(() => {});
}

function launchHandoffIfNeeded(
  sendId: string,
  ctx: SendExecutionContext,
  onProgress?: (message: string) => void,
): void {
  if (current && BackgroundSendService.isSafeToCloseApp(current)) return;
  if (
    handoffPinnedSendID
    && handoffPromise
    && handoffPinnedSendID !== sendId
  ) {
    return;
  }
  if (handoffPromise) return;

  isHandoffRunning = true;
  handoffPinnedSendID = sendId;
  handoffPinnedWalletID = ctx.walletId;
  activeSendID = sendId;
  retainedContexts.set(sendId, ctx);

  handoffPromise = (async () => {
    if (!current) {
      const record = resolvePendingTransfer(sendId);
      if (record) current = record;
    }
    await performHandoffWork(sendId, ctx, onProgress);
  })()
    .catch(async (error) => {
      const message = error instanceof Error ? error.message : 'Send failed';
      markHandoffFailed(sendId, message);
    })
    .finally(() => {
      isHandoffRunning = false;
      handoffPromise = null;
      clearHandoffPins();
    });
}

/** iOS: MeshBackgroundSendService */
export const BackgroundSendService = {
  isHandoffRunning(): boolean {
    return isHandoffRunning || handoffPromise != null;
  },

  getActiveSendID(): string | null {
    return activeSendID;
  },

  isSafeToCloseApp(record: PendingSendRecord | null | undefined): boolean {
    return record?.handoffRegistered === true;
  },

  getExecutionContext(sendId: string): SendExecutionContext | null {
    return retainedContexts.get(sendId) ?? null;
  },

  executionContextFromRecord,

  async resolveRecord(sendId: string): Promise<PendingSendRecord | null> {
    return resolvePendingRecord(sendId);
  },

  /** Creates pending row before submitted screen (iOS: prepareForHandoff). */
  async prepareForHandoff(ctx: SendExecutionContext): Promise<string> {
    await ensureHydrated();

    const record = buildPendingTransfer(ctx, 'Starting…');
    await attachChainUSDTAtStart(record, ctx);

    activeSendID = record.id;
    current = record;
    retainedContexts.set(record.id, ctx);
    await persist(record);
    return record.id;
  },

  /** Signs + registers in background; safe to show submitted screen immediately. */
  startHandoffForPendingSend(
    sendId: string,
    ctx: SendExecutionContext,
    onProgress?: (message: string) => void,
  ): void {
    retainedContexts.set(sendId, ctx);
    launchHandoffIfNeeded(sendId, ctx, onProgress);
  },

  async awaitHandoff(sendId: string): Promise<void> {
    if (handoffPinnedSendID === sendId && handoffPromise) {
      await handoffPromise;
    }
  },

  /** Resume in-flight handoff after extension reload (iOS: prepareForBackgroundContinuation). */
  async restoreAndResume(): Promise<void> {
    await ensureHydrated();

    const inFlight = trackedTransfers.find(
      (item) => item.status === 'processing' && !item.handoffRegistered,
    );
    if (!inFlight) return;

    current = inFlight;
    activeSendID = inFlight.id;

    const ctx = retainedContexts.get(inFlight.id) ?? executionContextFromRecord(inFlight);
    retainedContexts.set(inFlight.id, ctx);

    if (!this.isHandoffRunning()) {
      this.startHandoffForPendingSend(inFlight.id, ctx);
    }
  },

  /** Keep in-memory cache aligned when poll service updates storage. */
  syncFromStore(record: PendingSendRecord): void {
    upsertTracked(record);
    if (current?.id === record.id) current = record;
  },
};
