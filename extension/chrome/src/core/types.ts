export type WalletImportKind = 'mnemonic' | 'privateKey';

export interface StoredWallet {
  id: string;
  name: string;
  address: string;
  createdAt: string;
  importKind: WalletImportKind;
}

export type TransferStatus = 'processing' | 'confirmed' | 'failed';

export interface WalletTransaction {
  id: string;
  kind: 'sent' | 'received';
  title: string;
  subtitle: string;
  amountUSDT: number;
  dayLabel: string;
  txID: string;
  fromAddress: string;
  toAddress: string;
  timestamp: string;
  transferStatus: TransferStatus;
  failureMessage?: string;
}

export interface ReceiveSlot {
  index: number;
  address: string;
  title: string;
  derivationPath: string;
  balanceUSDT?: number | null;
}

export interface PrivacySpendSource {
  address: string;
  derivationPath: string;
  accountIndex: number;
  isPrivateSpend: boolean;
}

export interface PendingSendRecord {
  id: string;
  walletID: string;
  recipientAddress: string;
  amountText: string;
  amountUSDT: number;
  isPrivateSendMode: boolean;
  selectedSendSlotIndex: number;
  stepMessage: string;
  startedAt: string;
  txID: string;
  fromAddress: string;
  toAddress: string;
  status: TransferStatus;
  failedMessage?: string;
  handoffRegistered: boolean;
  workerQueued: boolean;
  handoffResumeJSON?: string;
  chainUSDTAtStart?: string;
}

export interface SendHandoffResult {
  obligationID: string;
  userAddress: string;
  signedMainTxJSON: string | null;
  signedMainTxSteps: QueuedSendStep[] | null;
  highEnergy: boolean;
  isPrivateSend: boolean;
  sendMode: 'direct' | 'private';
}

export interface QueuedSendStep {
  fromAddress: string;
  toAddress: string;
  amountUSDT: number;
  signedTxJSON: string;
  highEnergy: boolean;
  label: string;
}

export interface SendStatusResponse {
  ok: boolean;
  id?: string;
  status?: string;
  mainTxID?: string;
  feeTxID?: string;
  lastError?: string;
  currentStepIndex?: number;
  totalSteps?: number;
  lastStepLabel?: string;
  lastStepTxID?: string;
  networkStartedAtMs?: number;
  queueAttempts?: number;
  isPrivateSend?: boolean;
  hasSignedMain?: boolean;
}

export type ActivityFilter = 'all' | 'received' | 'sent';

export type AppRoute = 'splash' | 'lock' | 'onboarding' | 'wallet';

export type OnboardingStep =
  | 'welcome'
  | 'createIntro'
  | 'showRecovery'
  | 'addExisting'
  | 'seedSecurity'
  | 'restorePhrase'
  | 'restorePrivateKey'
  | 'createLaunch'
  | 'setupPassword'
  | 'confirmPassword'
  | 'walletReady';

export type SendStep = 'address' | 'review' | 'preparing' | 'submitted' | 'success' | 'failed';

export interface DeepRecoveryState {
  isRunning: boolean;
  progressChecked: number;
  progressTotal: number;
  isTransferring: boolean;
  statusMessage: string | null;
  errorMessage: string | null;
}

export type Language = 'en' | 'tr' | 'vi' | 'id' | 'es';
