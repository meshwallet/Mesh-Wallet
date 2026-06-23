package com.mesh.wallet.ui.wallet

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.mesh.wallet.R
import com.mesh.wallet.core.l10n.L10n
import com.mesh.wallet.core.session.WalletSession
import com.mesh.wallet.data.tron.TronUSDTService
import com.mesh.wallet.domain.model.StoredWallet
import com.mesh.wallet.domain.model.WalletImportKind
import com.mesh.wallet.ui.components.MeshPrimaryButton
import com.mesh.wallet.ui.components.MeshSecondaryButton
import com.mesh.wallet.ui.security.MeshPasscodeVerifySheet
import com.mesh.wallet.ui.security.MeshWalletRecoveryPhraseSheet
import com.mesh.wallet.ui.theme.MeshColors
import com.mesh.wallet.ui.theme.MeshMetrics
import com.mesh.wallet.ui.theme.MeshTypography

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SelectWalletSheet(
    visible: Boolean,
    wallets: List<StoredWallet>,
    activeWalletId: String?,
    session: WalletSession,
    onDismiss: () -> Unit,
    onSelect: (String) -> Unit,
    onWalletRenamed: () -> Unit = {},
    onWalletRemoved: (String) -> Unit = {},
    onAddExisting: () -> Unit = {},
    onCreateNew: () -> Unit = {}
) {
    if (!visible) return
    val context = LocalContext.current
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    var openMenuWalletId by remember { mutableStateOf<String?>(null) }
    var walletPendingRename by remember { mutableStateOf<StoredWallet?>(null) }
    var walletPendingBackup by remember { mutableStateOf<StoredWallet?>(null) }
    var walletPendingRemoval by remember { mutableStateOf<StoredWallet?>(null) }
    var showRemoveConfirm by remember { mutableStateOf(false) }
    var showBackupVerify by remember { mutableStateOf(false) }
    var showRemoveVerify by remember { mutableStateOf(false) }
    var recoveryWords by remember { mutableStateOf<List<String>?>(null) }

    val canRemoveWallets = wallets.size > 1

    MeshRenameWalletSheet(
        visible = walletPendingRename != null,
        walletId = walletPendingRename?.id.orEmpty(),
        currentName = walletPendingRename?.name.orEmpty(),
        session = session,
        onSaved = {
            walletPendingRename = null
            onWalletRenamed()
        },
        onDismiss = { walletPendingRename = null }
    )

    MeshPasscodeVerifySheet(
        visible = showBackupVerify,
        session = session,
        title = L10n.WalletSelect.menuBackup(context),
        subtitle = L10n.tr(context, "settings_view_recovery_subtitle"),
        onVerified = {
            showBackupVerify = false
            val id = walletPendingBackup?.id
            recoveryWords = id?.let { session.secureStorage.loadMnemonic(it) }
        },
        onDismiss = {
            showBackupVerify = false
            walletPendingBackup = null
        },
        showsBiometricRetry = true,
        biometricReason = L10n.tr(context, "settings_view_recovery_biometric_reason")
    )

    MeshPasscodeVerifySheet(
        visible = showRemoveVerify,
        session = session,
        title = L10n.WalletSelect.menuRemove(context),
        subtitle = L10n.tr(context, "settings_recovery_requires_passcode"),
        onVerified = {
            showRemoveVerify = false
            walletPendingRemoval?.let { wallet ->
                session.walletService.removeWallet(wallet.id)
                session.reconcile()
                onWalletRemoved(wallet.id)
                walletPendingRemoval = null
                if (!session.registry.hasAnyWallet) onDismiss()
            }
        },
        onDismiss = {
            showRemoveVerify = false
            walletPendingRemoval = null
        },
        showsBiometricRetry = true,
        biometricReason = L10n.tr(context, "settings_remove_action")
    )

    MeshWalletRecoveryPhraseSheet(
        visible = recoveryWords != null,
        words = recoveryWords.orEmpty(),
        walletName = walletPendingBackup?.name,
        onDismiss = {
            recoveryWords = null
            walletPendingBackup = null
        }
    )

    if (showRemoveConfirm) {
        val wallet = walletPendingRemoval
        val supportsHd = wallet?.importKind == WalletImportKind.MNEMONIC
        AlertDialog(
            onDismissRequest = {
                showRemoveConfirm = false
                walletPendingRemoval = null
            },
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
                    Text(L10n.WalletSelect.menuRemove(context), color = MeshColors.Warning)
                }
            },
            dismissButton = {
                TextButton(onClick = {
                    showRemoveConfirm = false
                    walletPendingRemoval = null
                }) {
                    Text(L10n.Common.cancel(context))
                }
            },
            containerColor = MeshColors.Surface
        )
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = MeshColors.Background
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp)
                .padding(bottom = 24.dp)
        ) {
            Text(
                text = L10n.WalletSelect.title(context),
                style = MeshTypography.SectionTitle,
                color = MeshColors.TextPrimary,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 8.dp, bottom = 20.dp),
                textAlign = androidx.compose.ui.text.style.TextAlign.Center
            )

            Column(
                modifier = Modifier.verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                wallets.forEach { wallet ->
                    WalletRow(
                        wallet = wallet,
                        selected = wallet.id == activeWalletId,
                        menuExpanded = openMenuWalletId == wallet.id,
                        onMenuToggle = { openMenuWalletId = if (openMenuWalletId == wallet.id) null else wallet.id },
                        onDismissMenu = { openMenuWalletId = null },
                        onClick = { onSelect(wallet.id) },
                        onRename = {
                            openMenuWalletId = null
                            walletPendingRename = wallet
                        },
                        onBackup = if (wallet.importKind == WalletImportKind.MNEMONIC) {
                            {
                                openMenuWalletId = null
                                walletPendingBackup = wallet
                                showBackupVerify = true
                            }
                        } else null,
                        onRemove = if (canRemoveWallets) {
                            {
                                openMenuWalletId = null
                                walletPendingRemoval = wallet
                                showRemoveConfirm = true
                            }
                        } else null
                    )
                }
            }

            Spacer(modifier = Modifier.height(16.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                MeshSecondaryButton(
                    title = L10n.WalletSelect.addExisting(context),
                    onClick = {
                        onAddExisting()
                        onDismiss()
                    },
                    modifier = Modifier.weight(1f)
                )
                MeshPrimaryButton(
                    title = L10n.WalletSelect.createNew(context),
                    onClick = {
                        onCreateNew()
                        onDismiss()
                    },
                    modifier = Modifier.weight(1f)
                )
            }
        }
    }
}

@Composable
private fun WalletRow(
    wallet: StoredWallet,
    selected: Boolean,
    menuExpanded: Boolean,
    onMenuToggle: () -> Unit,
    onDismissMenu: () -> Unit,
    onClick: () -> Unit,
    onRename: () -> Unit,
    onBackup: (() -> Unit)?,
    onRemove: (() -> Unit)?
) {
    val context = LocalContext.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(
                androidx.compose.ui.graphics.Color.Black.copy(alpha = 0.34f),
                RoundedCornerShape(MeshMetrics.WalletCardRadius)
            )
            .border(
                width = if (selected) 1.5.dp else 1.dp,
                color = if (selected) MeshColors.Accent.copy(alpha = 0.55f) else MeshColors.BorderSubtle,
                shape = RoundedCornerShape(MeshMetrics.WalletCardRadius)
            )
            .clickable(onClick = onClick)
            .padding(start = 12.dp, top = 12.dp, bottom = 12.dp, end = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        BoxIcon()
        Column(modifier = Modifier.weight(1f).padding(horizontal = 14.dp)) {
            Text(
                wallet.name,
                style = MeshTypography.Body.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold),
                color = MeshColors.TextPrimary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Text(
                TronUSDTService.shortAddress(wallet.address),
                style = MeshTypography.Caption,
                color = MeshColors.TextSecondary,
                maxLines = 1
            )
        }
        Box {
            IconButton(onClick = onMenuToggle) {
                Icon(Icons.Default.MoreVert, contentDescription = null, tint = MeshColors.TextSecondary)
            }
            DropdownMenu(
                expanded = menuExpanded,
                onDismissRequest = onDismissMenu,
                containerColor = MeshColors.Surface
            ) {
                DropdownMenuItem(
                    text = { Text(L10n.WalletSelect.menuRename(context)) },
                    onClick = onRename
                )
                onBackup?.let { backup ->
                    DropdownMenuItem(
                        text = { Text(L10n.WalletSelect.menuBackup(context)) },
                        onClick = backup
                    )
                }
                onRemove?.let { remove ->
                    DropdownMenuItem(
                        text = { Text(L10n.WalletSelect.menuRemove(context), color = MeshColors.Warning) },
                        onClick = remove
                    )
                }
            }
        }
    }
}

@Composable
private fun BoxIcon() {
    Box(
        modifier = Modifier
            .size(40.dp)
            .background(androidx.compose.ui.graphics.Color.Black.copy(alpha = 0.38f), RoundedCornerShape(10.dp)),
        contentAlignment = Alignment.Center
    ) {
        Image(
            painter = painterResource(R.drawable.ic_wallet),
            contentDescription = null,
            modifier = Modifier.size(20.dp)
        )
    }
}
