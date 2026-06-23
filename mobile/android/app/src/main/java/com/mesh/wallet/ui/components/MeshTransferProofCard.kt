package com.mesh.wallet.ui.components

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.mesh.wallet.R
import com.mesh.wallet.core.l10n.L10n
import com.mesh.wallet.domain.model.TransactionDirection
import com.mesh.wallet.domain.model.WalletTransaction
import com.mesh.wallet.domain.model.formattedDateTime
import com.mesh.wallet.domain.model.proofAmountText
import com.mesh.wallet.domain.model.proofShortCounterparty
import com.mesh.wallet.domain.model.proofShortTxId
import com.mesh.wallet.ui.theme.MeshColors
import com.mesh.wallet.ui.theme.MeshMetrics
import com.mesh.wallet.ui.theme.MeshTypography

@Composable
fun MeshTransferProofCard(transaction: WalletTransaction, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    Column(
        modifier = modifier
            .fillMaxWidth()
            .background(MeshColors.ListCardFill.copy(alpha = 0.55f), RoundedCornerShape(MeshMetrics.CardRadius))
            .padding(24.dp)
    ) {
        Text(
            text = transaction.proofAmountText(),
            style = MeshTypography.BalanceHero.copy(fontSize = 40.sp),
            color = MeshColors.TextPrimary,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
        Spacer(modifier = Modifier.height(24.dp))
        ProofRow(L10n.tr(context, "transfer_proof_status"), L10n.tr(context, "transfer_proof_confirmed"))
        Divider()
        ProofRow(L10n.tr(context, "transfer_proof_network_label"), L10n.tr(context, "transfer_proof_network"))
        Divider()
        val counterpartyLabel = if (transaction.direction == TransactionDirection.OUTGOING) {
            L10n.tr(context, "transfer_proof_to")
        } else {
            L10n.tr(context, "transfer_proof_from")
        }
        ProofRow(counterpartyLabel, transaction.proofShortCounterparty())
        transaction.txId?.let {
            Divider()
            ProofRow(L10n.tr(context, "transfer_proof_tx"), transaction.proofShortTxId())
        }
        Divider()
        ProofRow(L10n.tr(context, "transfer_proof_date"), transaction.formattedDateTime())
        Spacer(modifier = Modifier.height(28.dp))
        Column(modifier = Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
            Image(painter = painterResource(R.drawable.icon_png), contentDescription = null, modifier = Modifier.size(80.dp))
            Text(L10n.tr(context, "transfer_proof_tagline"), style = MeshTypography.Caption, color = MeshColors.TextTertiary)
        }
    }
}

@Composable
private fun ProofRow(label: String, value: String) {
    Row(modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalAlignment = Alignment.Top) {
        Text(label, style = MeshTypography.Label, color = MeshColors.TextTertiary, modifier = Modifier.weight(0.35f))
        Text(value, style = MeshTypography.Body, color = MeshColors.TextPrimary, modifier = Modifier.weight(0.65f), maxLines = 2, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
private fun Divider() {
    HorizontalDivider(color = MeshColors.BorderSubtle, modifier = Modifier.padding(vertical = 4.dp))
}
