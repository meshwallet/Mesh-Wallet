package com.mesh.wallet.ui.wallet

import android.content.Intent
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.mesh.wallet.core.l10n.L10n
import com.mesh.wallet.domain.model.TransactionDirection
import com.mesh.wallet.domain.model.WalletTransaction
import com.mesh.wallet.domain.model.proofShareText
import com.mesh.wallet.ui.components.MeshPrimaryButton
import com.mesh.wallet.ui.components.MeshTransferProofCard
import com.mesh.wallet.ui.theme.MeshColors
import com.mesh.wallet.ui.theme.MeshMetrics
import com.mesh.wallet.ui.theme.MeshTypography

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TransactionDetailSheet(transaction: WalletTransaction?, onDismiss: () -> Unit) {
    val tx = transaction ?: return
    val context = LocalContext.current
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState, containerColor = MeshColors.Background) {
        Column(modifier = Modifier.padding(MeshMetrics.ScreenPadding)) {
            Text(
                if (tx.direction == TransactionDirection.INCOMING) {
                    L10n.tr(context, "transaction_received")
                } else {
                    L10n.tr(context, "transaction_sent")
                },
                style = MeshTypography.ScreenTitle,
                color = MeshColors.TextPrimary
            )
            Spacer(modifier = Modifier.height(16.dp))
            MeshTransferProofCard(transaction = tx)
            Spacer(modifier = Modifier.height(16.dp))
            MeshPrimaryButton(
                title = L10n.tr(context, "transfer_proof_share"),
                onClick = {
                    val intent = Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_TEXT, tx.proofShareText())
                    }
                    context.startActivity(Intent.createChooser(intent, L10n.tr(context, "transfer_proof_share")))
                },
                modifier = Modifier.fillMaxWidth()
            )
            Spacer(modifier = Modifier.height(24.dp))
        }
    }
}
