package com.mesh.wallet.ui.security

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.ExperimentalMaterial3Api
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
import androidx.compose.ui.unit.dp
import com.mesh.wallet.core.l10n.L10n
import com.mesh.wallet.core.session.WalletSession
import com.mesh.wallet.data.secure.SecureStorage
import com.mesh.wallet.ui.components.MeshPasscodeDots
import com.mesh.wallet.ui.components.MeshPasscodeEntryLayout
import com.mesh.wallet.ui.components.MeshPasscodeKeypad
import com.mesh.wallet.ui.theme.MeshColors
import com.mesh.wallet.ui.theme.MeshMetrics
import com.mesh.wallet.ui.theme.MeshTypography

private enum class ChangePasscodeStep { VerifyCurrent, EnterNew, ConfirmNew }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChangePasscodeFlowScreen(
    visible: Boolean,
    session: WalletSession,
    onDismiss: () -> Unit,
    onSuccess: () -> Unit
) {
    if (!visible) return
    val context = LocalContext.current
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var step by remember { mutableStateOf(ChangePasscodeStep.VerifyCurrent) }
    var verifiedCurrent by remember { mutableStateOf<String?>(null) }
    var newPasscode by remember { mutableStateOf<String?>(null) }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = MeshColors.Background
    ) {
        when (step) {
            ChangePasscodeStep.VerifyCurrent -> PasscodeEntry(
                title = L10n.tr(context, "security_lock_title"),
                subtitle = L10n.tr(context, "settings_passcode_change"),
                onCancel = onDismiss,
                verify = { session.secureStorage.verifyPasscode(it) },
                onComplete = {
                    verifiedCurrent = it
                    step = ChangePasscodeStep.EnterNew
                }
            )
            ChangePasscodeStep.EnterNew -> PasscodeEntry(
                title = L10n.tr(context, "security_create_passcode"),
                subtitle = L10n.tr(context, "settings_passcode_change"),
                onCancel = { step = ChangePasscodeStep.VerifyCurrent },
                verify = { it != verifiedCurrent },
                onComplete = {
                    newPasscode = it
                    step = ChangePasscodeStep.ConfirmNew
                },
                mismatchMessage = L10n.tr(context, "security_passcode_same_as_current")
            )
            ChangePasscodeStep.ConfirmNew -> PasscodeEntry(
                title = L10n.tr(context, "security_confirm_passcode"),
                subtitle = L10n.tr(context, "settings_passcode_change"),
                onCancel = { step = ChangePasscodeStep.EnterNew },
                verify = { it == newPasscode },
                onComplete = {
                    session.secureStorage.setPasscode(it)
                    onSuccess()
                    onDismiss()
                },
                mismatchMessage = L10n.tr(context, "onboarding_passcode_mismatch")
            )
        }
    }
}

@Composable
private fun PasscodeEntry(
    title: String,
    subtitle: String,
    onCancel: () -> Unit,
    verify: (String) -> Boolean,
    onComplete: (String) -> Unit,
    mismatchMessage: String = L10n.tr(LocalContext.current, "security_passcode_incorrect")
) {
    var entered by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }

    MeshPasscodeEntryLayout(
        modifier = Modifier
            .fillMaxSize()
            .background(MeshColors.Background)
            .padding(horizontal = MeshMetrics.ScreenPadding),
        header = {
            Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Spacer(modifier = Modifier.weight(1f))
                TextButton(onClick = onCancel) {
                    Text(L10n.Common.cancel(LocalContext.current), color = MeshColors.TextSecondary)
                }
            }
        }
    ) {
        Spacer(modifier = Modifier.height(12.dp))
        Text(title, style = MeshTypography.ScreenTitle, color = MeshColors.TextPrimary)
        Spacer(modifier = Modifier.height(8.dp))
        Text(subtitle, style = MeshTypography.Secondary, color = MeshColors.TextSecondary)
        error?.let {
            Spacer(modifier = Modifier.height(12.dp))
            Text(it, style = MeshTypography.Caption, color = MeshColors.Warning)
        }
        Spacer(modifier = Modifier.height(32.dp))
        MeshPasscodeDots(enteredCount = entered.length, modifier = Modifier.align(Alignment.CenterHorizontally))
        Spacer(modifier = Modifier.weight(1f))
        MeshPasscodeKeypad(
            onDigit = { digit ->
                if (entered.length < SecureStorage.PASSCODE_LENGTH) {
                    entered += digit
                    error = null
                    if (entered.length == SecureStorage.PASSCODE_LENGTH) {
                        if (verify(entered)) {
                            onComplete(entered)
                            entered = ""
                        } else {
                            error = mismatchMessage
                            entered = ""
                        }
                    }
                }
            },
            onDelete = {
                if (entered.isNotEmpty()) entered = entered.dropLast(1)
                error = null
            }
        )
        Spacer(modifier = Modifier.height(32.dp))
    }
}
