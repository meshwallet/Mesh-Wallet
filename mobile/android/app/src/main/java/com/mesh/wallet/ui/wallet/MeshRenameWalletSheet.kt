package com.mesh.wallet.ui.wallet

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.mesh.wallet.core.l10n.L10n
import com.mesh.wallet.core.session.WalletSession
import com.mesh.wallet.ui.components.MeshPrimaryButton
import com.mesh.wallet.ui.theme.MeshColors
import com.mesh.wallet.ui.theme.MeshMetrics
import com.mesh.wallet.ui.theme.MeshTypography

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MeshRenameWalletSheet(
    visible: Boolean,
    walletId: String,
    currentName: String,
    session: WalletSession,
    onSaved: () -> Unit,
    onDismiss: () -> Unit
) {
    if (!visible) return
    val context = LocalContext.current
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var name by remember(walletId, currentName) { mutableStateOf(currentName) }
    var nameError by remember { mutableStateOf<String?>(null) }

    fun validate() {
        val trimmed = name.trim()
        if (trimmed.isEmpty()) {
            nameError = null
            return
        }
        val taken = session.registry.wallets.any {
            it.id != walletId && it.name.equals(trimmed, ignoreCase = true)
        }
        nameError = if (taken) L10n.tr(context, "error_wallet_name_taken") else null
    }

    val trimmed = name.trim()
    val canSave = trimmed.isNotEmpty() && trimmed != currentName && nameError == null

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = MeshColors.Background
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(MeshMetrics.ScreenPadding)
        ) {
            Text(
                L10n.WalletSelect.menuRename(context),
                style = MeshTypography.ScreenTitle,
                color = MeshColors.TextPrimary,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth()
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                L10n.tr(context, "wallet_rename_subtitle"),
                style = MeshTypography.Secondary,
                color = MeshColors.TextSecondary,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth()
            )
            Spacer(modifier = Modifier.height(28.dp))
            OutlinedTextField(
                value = name,
                onValueChange = {
                    name = it
                    validate()
                },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = MeshColors.Accent,
                    unfocusedBorderColor = MeshColors.Border,
                    focusedContainerColor = MeshColors.FieldFill,
                    unfocusedContainerColor = MeshColors.FieldFill,
                    focusedTextColor = MeshColors.TextPrimary,
                    unfocusedTextColor = MeshColors.TextPrimary
                ),
                shape = RoundedCornerShape(MeshMetrics.FieldRadius)
            )
            nameError?.let {
                Spacer(modifier = Modifier.height(8.dp))
                Text(it, style = MeshTypography.Caption, color = MeshColors.Warning)
            }
            Spacer(modifier = Modifier.weight(1f))
            MeshPrimaryButton(
                title = L10n.tr(context, "wallet_address_drawer_rename_action"),
                onClick = {
                    session.registry.renameWallet(walletId, trimmed)
                    onSaved()
                    onDismiss()
                },
                enabled = canSave
            )
            Spacer(modifier = Modifier.height(16.dp))
        }
    }
}
