package com.mesh.wallet.ui.security

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.mesh.wallet.core.config.MeshAppLinks
import com.mesh.wallet.core.l10n.L10n
import com.mesh.wallet.core.security.MeshBiometricAuth
import com.mesh.wallet.core.session.WalletSession
import com.mesh.wallet.domain.model.WalletImportKind
import com.mesh.wallet.ui.components.MeshCloseButton
import com.mesh.wallet.ui.components.MeshSecondaryButton
import com.mesh.wallet.ui.theme.MeshColors
import com.mesh.wallet.ui.theme.MeshMetrics
import com.mesh.wallet.ui.theme.MeshTypography

@Composable
fun WalletSecurityScreen(
    session: WalletSession,
    onBack: () -> Unit,
    onWalletRemoved: () -> Unit
) {
    val context = LocalContext.current
    val biometricName = MeshBiometricAuth.displayName(context)
    var biometricEnabled by remember { mutableStateOf(session.secureStorage.isBiometricEnabled()) }
    var showChangePasscode by remember { mutableStateOf(false) }
    var showRecoveryVerify by remember { mutableStateOf(false) }
    var showRemoveVerify by remember { mutableStateOf(false) }
    var showRemoveConfirm by remember { mutableStateOf(false) }
    var showPasscodeUpdated by remember { mutableStateOf(false) }
    var recoveryWords by remember { mutableStateOf<List<String>?>(null) }
    val wallet by session.activeWallet.collectAsState()
    val supportsHd = wallet?.importKind == WalletImportKind.MNEMONIC

    val biometricSubtitle = when {
        !session.secureStorage.isPasscodeEnabled() -> L10n.tr(context, "settings_biometric_setup_first")
        !MeshBiometricAuth.isAvailable(context) -> L10n.tr(context, "settings_biometric_unavailable_device")
        else -> L10n.tr(context, "settings_biometric_unlock_hint", biometricName)
    }

    ChangePasscodeFlowScreen(
        visible = showChangePasscode,
        session = session,
        onDismiss = { showChangePasscode = false },
        onSuccess = { showPasscodeUpdated = true }
    )
    MeshPasscodeVerifySheet(
        visible = showRecoveryVerify,
        session = session,
        title = L10n.tr(context, "settings_view_recovery_phrase"),
        subtitle = L10n.tr(context, "settings_view_recovery_subtitle"),
        onVerified = {
            showRecoveryVerify = false
            val id = session.registry.activeWalletId
            recoveryWords = id?.let { session.secureStorage.loadMnemonic(it) }
        },
        onDismiss = { showRecoveryVerify = false },
        showsBiometricRetry = true,
        biometricReason = L10n.tr(context, "settings_view_recovery_biometric_reason")
    )
    MeshPasscodeVerifySheet(
        visible = showRemoveVerify,
        session = session,
        title = L10n.tr(context, "settings_remove_action"),
        subtitle = L10n.tr(context, "settings_recovery_requires_passcode"),
        onVerified = {
            showRemoveVerify = false
            wallet?.let { w ->
                session.walletService.removeWallet(w.id)
                session.reconcile()
                onWalletRemoved()
            }
        },
        onDismiss = { showRemoveVerify = false },
        showsBiometricRetry = true,
        biometricReason = L10n.tr(context, "settings_remove_action")
    )
    MeshWalletRecoveryPhraseSheet(
        visible = recoveryWords != null,
        words = recoveryWords.orEmpty(),
        walletName = wallet?.name,
        onDismiss = { recoveryWords = null }
    )

    if (showRemoveConfirm) {
        AlertDialog(
            onDismissRequest = { showRemoveConfirm = false },
            title = { Text(L10n.tr(context, "settings_remove_confirm_title")) },
            text = {
                Text(
                    if (supportsHd) L10n.tr(context, "settings_remove_confirm_phrase")
                    else L10n.tr(context, "settings_remove_confirm_key")
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    showRemoveConfirm = false
                    showRemoveVerify = true
                }) {
                    Text(L10n.tr(context, "settings_remove_action"), color = MeshColors.Warning)
                }
            },
            dismissButton = {
                TextButton(onClick = { showRemoveConfirm = false }) {
                    Text(L10n.Common.cancel(context))
                }
            },
            containerColor = MeshColors.Surface
        )
    }
    if (showPasscodeUpdated) {
        AlertDialog(
            onDismissRequest = { showPasscodeUpdated = false },
            title = { Text(L10n.tr(context, "settings_passcode_updated_title")) },
            text = { Text(L10n.tr(context, "settings_passcode_updated_message")) },
            confirmButton = {
                TextButton(onClick = { showPasscodeUpdated = false }) {
                    Text(L10n.Common.ok(context))
                }
            },
            containerColor = MeshColors.Surface
        )
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MeshColors.Background)
            .padding(MeshMetrics.ScreenPadding)
    ) {
        MeshCloseButton(onClick = onBack)
        Spacer(modifier = Modifier.height(24.dp))
        Text(L10n.tr(context, "settings_title"), style = MeshTypography.ScreenTitle, color = MeshColors.TextPrimary)
        Spacer(modifier = Modifier.height(24.dp))

        Column(modifier = Modifier.weight(1f).verticalScroll(rememberScrollState())) {
            SecurityCard {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(biometricName, style = MeshTypography.Body.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold), color = MeshColors.TextPrimary)
                        Spacer(modifier = Modifier.height(6.dp))
                        Text(biometricSubtitle, style = MeshTypography.Caption, color = MeshColors.TextSecondary)
                    }
                    Switch(
                        checked = biometricEnabled,
                        onCheckedChange = {
                            biometricEnabled = it
                            session.secureStorage.setBiometricEnabled(it)
                        },
                        enabled = session.secureStorage.isPasscodeEnabled() && MeshBiometricAuth.isAvailable(context),
                        colors = SwitchDefaults.colors(checkedThumbColor = MeshColors.Accent, checkedTrackColor = MeshColors.AccentMuted)
                    )
                }
            }
            Spacer(modifier = Modifier.height(12.dp))
            SecurityRow(
                title = L10n.tr(context, "settings_passcode"),
                subtitle = L10n.tr(context, "settings_passcode_change"),
                onClick = { showChangePasscode = true }
            )
            if (supportsHd) {
                Spacer(modifier = Modifier.height(12.dp))
                SecurityRow(
                    title = L10n.tr(context, "settings_view_recovery_phrase"),
                    subtitle = L10n.tr(context, "settings_recovery_requires_passcode"),
                    onClick = { showRecoveryVerify = true }
                )
            }
            Spacer(modifier = Modifier.height(12.dp))
            SecurityRow(
                title = L10n.tr(context, "settings_remove_wallet"),
                destructive = true,
                onClick = { showRemoveConfirm = true }
            )
        }

        MeshSecondaryButton(
            title = L10n.tr(context, "settings_contact_support"),
            onClick = { MeshAppLinks.openContactSupport(context) }
        )
        Spacer(modifier = Modifier.height(8.dp))
    }
}

@Composable
private fun SecurityCard(content: @Composable () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(MeshColors.ListCardFill, RoundedCornerShape(MeshMetrics.WalletCardRadius))
            .padding(18.dp)
    ) {
        content()
    }
}

@Composable
private fun SecurityRow(
    title: String,
    subtitle: String? = null,
    destructive: Boolean = false,
    onClick: (() -> Unit)? = null
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(MeshColors.ListCardFill, RoundedCornerShape(MeshMetrics.WalletCardRadius))
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(horizontal = 18.dp, vertical = 16.dp)
    ) {
        Text(title, style = MeshTypography.Body.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold), color = if (destructive) MeshColors.Warning else MeshColors.TextPrimary)
        subtitle?.let {
            Spacer(modifier = Modifier.height(4.dp))
            Text(it, style = MeshTypography.Caption, color = MeshColors.TextSecondary)
        }
    }
}
