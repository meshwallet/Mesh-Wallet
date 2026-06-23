package com.mesh.wallet.ui.privacy

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.mesh.wallet.core.l10n.L10n
import com.mesh.wallet.core.session.WalletSession
import com.mesh.wallet.ui.components.MeshCloseButton
import com.mesh.wallet.ui.components.MeshPrimaryButton
import com.mesh.wallet.ui.theme.MeshColors
import com.mesh.wallet.ui.theme.MeshMetrics
import com.mesh.wallet.ui.theme.MeshTypography

@Composable
fun WalletPrivacyScreen(session: WalletSession, onBack: () -> Unit) {
    val context = LocalContext.current
    val walletId = session.registry.activeWalletId
    val recovery = session.deepRecoveryService
    val isRunning by recovery.isRunning.collectAsState()
    val progress by recovery.progressChecked.collectAsState()
    val total by recovery.progressTotal.collectAsState()
    val status by recovery.statusMessage.collectAsState()
    val error by recovery.errorMessage.collectAsState()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MeshColors.Background)
            .padding(MeshMetrics.ScreenPadding)
    ) {
        MeshCloseButton(onClick = onBack)
        Spacer(modifier = Modifier.height(24.dp))
        Text(L10n.tr(context, "privacy_title"), style = MeshTypography.ScreenTitle, color = MeshColors.TextPrimary)
        Spacer(modifier = Modifier.height(12.dp))
        Text(L10n.tr(context, "privacy_subtitle"), style = MeshTypography.Secondary, color = MeshColors.TextSecondary)
        Spacer(modifier = Modifier.height(32.dp))

        Text(L10n.tr(context, "send_deep_recovery_title"), style = MeshTypography.SectionTitle, color = MeshColors.TextPrimary)
        Spacer(modifier = Modifier.height(8.dp))
        Text(L10n.tr(context, "send_deep_recovery_subtitle"), style = MeshTypography.Caption, color = MeshColors.TextSecondary)
        Spacer(modifier = Modifier.height(16.dp))

        if (isRunning) {
            LinearProgressIndicator(
                progress = { if (total > 0) progress.toFloat() / total else 0f },
                modifier = Modifier.fillMaxWidth(),
                color = MeshColors.Accent,
                trackColor = MeshColors.Surface
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text("$progress / $total", style = MeshTypography.Caption, color = MeshColors.TextSecondary)
        }

        status?.let {
            Spacer(modifier = Modifier.height(8.dp))
            Text(it, style = MeshTypography.Body, color = MeshColors.Success)
        }
        error?.let {
            Spacer(modifier = Modifier.height(8.dp))
            Text(it, style = MeshTypography.Body, color = MeshColors.Warning)
        }

        Spacer(modifier = Modifier.height(16.dp))
        MeshPrimaryButton(
            title = L10n.tr(context, "send_deep_recovery_start"),
            enabled = !isRunning,
            onClick = { recovery.start(walletId) }
        )
    }
}
