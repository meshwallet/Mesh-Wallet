package com.mesh.wallet.ui.send

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
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
import com.mesh.wallet.data.tron.TronUSDTService
import com.mesh.wallet.domain.model.WalletReceiveSlot
import com.mesh.wallet.ui.theme.MeshColors
import com.mesh.wallet.ui.theme.MeshMetrics
import com.mesh.wallet.ui.theme.MeshTypography

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MeshSendToSelfSheet(
    visible: Boolean,
    slots: List<WalletReceiveSlot>,
    onDismiss: () -> Unit,
    onSelect: (WalletReceiveSlot) -> Unit
) {
    if (!visible) return
    val context = LocalContext.current
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = MeshColors.Surface
    ) {
        Column(modifier = Modifier.padding(MeshMetrics.ScreenPadding)) {
            Text(
                L10n.Send.sendToSelf(context),
                style = MeshTypography.SectionTitle,
                color = MeshColors.TextPrimary,
                modifier = Modifier.padding(bottom = 16.dp)
            )
            slots.forEach { slot ->
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { onSelect(slot) }
                        .padding(vertical = 12.dp)
                ) {
                    Text(slot.name, style = MeshTypography.Body, color = MeshColors.TextPrimary)
                    Text(
                        TronUSDTService.shortAddress(slot.address),
                        style = MeshTypography.Caption,
                        color = MeshColors.TextSecondary
                    )
                }
            }
        }
    }
}
