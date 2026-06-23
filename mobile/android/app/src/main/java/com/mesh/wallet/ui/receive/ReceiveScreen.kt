package com.mesh.wallet.ui.receive

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.mesh.wallet.core.l10n.L10n
import com.mesh.wallet.core.session.WalletSession
import com.mesh.wallet.data.tron.TronUSDTService
import com.mesh.wallet.domain.model.WalletReceiveSlot
import com.mesh.wallet.ui.components.MeshFlowScreenHeader
import com.mesh.wallet.ui.components.MeshQRCode
import com.mesh.wallet.ui.components.MeshSecondaryButton
import com.mesh.wallet.ui.components.MeshWalletSlotPicker
import com.mesh.wallet.ui.theme.MeshColors
import com.mesh.wallet.ui.theme.MeshMetrics
import com.mesh.wallet.ui.theme.MeshTypography

@Composable
fun ReceiveScreen(session: WalletSession, onBack: () -> Unit) {
    val context = LocalContext.current
    val walletId = session.registry.activeWalletId
    var selectedSlotIndex by remember(walletId) {
        mutableIntStateOf(walletId?.let { session.privacyStore.selectedReceiveSlotIndex(it) } ?: 0)
    }
    var slots by remember { mutableStateOf<List<WalletReceiveSlot>>(emptyList()) }
    var address by remember { mutableStateOf<String?>(null) }
    var isLoading by remember { mutableStateOf(true) }
    var didCopy by remember { mutableStateOf(false) }
    val supportsHd = walletId?.let { session.credentials.supportsHdWalletFeatures(it) } == true

    LaunchedEffect(walletId) {
        if (walletId == null) return@LaunchedEffect
        isLoading = true
        slots = session.privacyService.listWalletReceiveSlots(walletId)
        selectedSlotIndex = session.privacyStore.selectedReceiveSlotIndex(walletId)
        isLoading = false
    }

    LaunchedEffect(walletId, selectedSlotIndex) {
        address = if (walletId != null) {
            if (supportsHd) {
                session.privacyService.receiveAddress(walletId, selectedSlotIndex)
            } else {
                session.registry.wallet(walletId)?.address
            }
        } else null
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MeshColors.Background)
    ) {
        MeshFlowScreenHeader(
            title = L10n.tr(context, "receive_title"),
            onClose = onBack
        )

        Column(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = MeshMetrics.ScreenPadding),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Spacer(modifier = Modifier.height(12.dp))
            val resolved = address
            if (resolved == null || isLoading) {
                CircularProgressIndicator(
                    color = MeshColors.Accent,
                    modifier = Modifier.align(Alignment.CenterHorizontally).padding(48.dp)
                )
            } else {
                MeshQRCode(content = resolved, modifier = Modifier.size(220.dp).align(Alignment.CenterHorizontally))
                Spacer(modifier = Modifier.height(16.dp))
                Text(
                    L10n.tr(context, "receive_private_hint"),
                    style = MeshTypography.Caption,
                    color = MeshColors.TextSecondary,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth()
                )

                if (supportsHd && slots.size > 1) {
                    Spacer(modifier = Modifier.height(24.dp))
                    MeshWalletSlotPicker(
                        headerTitle = L10n.tr(context, "receive_on_address"),
                        slots = slots,
                        selectedIndex = selectedSlotIndex,
                        onSelect = { index ->
                            selectedSlotIndex = index
                            walletId?.let { session.privacyStore.setSelectedReceiveSlotIndex(it, index) }
                        }
                    )
                }

                Spacer(modifier = Modifier.height(28.dp))
                Text(
                    text = TronUSDTService.shortAddress(resolved),
                    style = MeshTypography.Body,
                    color = MeshColors.TextPrimary,
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(MeshColors.FieldFill, RoundedCornerShape(50))
                        .clickable {
                            copyAddress(context, resolved)
                            didCopy = true
                        }
                        .padding(horizontal = 20.dp, vertical = 14.dp),
                    textAlign = TextAlign.Center
                )
                if (didCopy) {
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        L10n.Common.copied(context),
                        style = MeshTypography.Caption,
                        color = MeshColors.Success,
                        modifier = Modifier.fillMaxWidth(),
                        textAlign = TextAlign.Center
                    )
                }
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    "Network: Tron (TRC-20)",
                    style = MeshTypography.Caption,
                    color = MeshColors.TextTertiary,
                    modifier = Modifier.fillMaxWidth(),
                    textAlign = TextAlign.Center
                )
            }
        }

        val resolvedFooter = address
        if (resolvedFooter != null) {
            Column(modifier = Modifier.padding(MeshMetrics.ScreenPadding)) {
                MeshSecondaryButton(
                    title = L10n.tr(context, "receive_share_address"),
                    onClick = {
                        val shareText = "${L10n.tr(context, "receive_share_footer")}\n$resolvedFooter"
                        context.startActivity(
                            Intent.createChooser(
                                Intent(Intent.ACTION_SEND).apply {
                                    type = "text/plain"
                                    putExtra(Intent.EXTRA_TEXT, shareText)
                                },
                                L10n.tr(context, "receive_share_address")
                            )
                        )
                    }
                )
                Spacer(modifier = Modifier.height(8.dp))
            }
        }
    }
}

private fun copyAddress(context: Context, address: String) {
    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    clipboard.setPrimaryClip(ClipData.newPlainText("address", address))
    Toast.makeText(context, L10n.Common.copied(context), Toast.LENGTH_SHORT).show()
}
