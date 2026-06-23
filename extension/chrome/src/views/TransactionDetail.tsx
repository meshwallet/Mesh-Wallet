import type { WalletTransaction } from '@/core/types';
import { isProofEligible } from '@/utils/transaction-proof';
import { TransferProofExperience } from '@/components/TransferProofExperience';
import { TransactionTechnicalDetail } from '@/components/TransactionTechnicalDetail';

export function TransactionDetail({ tx, onClose }: { tx: WalletTransaction; onClose: () => void }) {
  if (isProofEligible(tx)) {
    return <TransferProofExperience tx={tx} onClose={onClose} usesSheetChrome />;
  }
  return <TransactionTechnicalDetail tx={tx} onClose={onClose} />;
}
