package com.mesh.wallet.ui.security

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.fragment.app.FragmentActivity
import com.mesh.wallet.core.l10n.L10n
import com.mesh.wallet.core.security.MeshBiometricAuth
import com.mesh.wallet.core.session.WalletSession
import com.mesh.wallet.data.secure.SecureStorage
import com.mesh.wallet.ui.components.MeshPasscodeDots
import com.mesh.wallet.ui.components.MeshPasscodeEntryLayout
import com.mesh.wallet.ui.components.MeshPasscodeKeypad
import com.mesh.wallet.ui.components.MeshPrimaryButton
import com.mesh.wallet.ui.theme.MeshColors
import com.mesh.wallet.ui.theme.MeshMetrics
import com.mesh.wallet.ui.theme.MeshTypography
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MeshPasscodeVerifySheet(
    visible: Boolean,
    session: WalletSession,
    title: String,
    subtitle: String,
    onVerified: () -> Unit,
    onDismiss: () -> Unit,
    showsBiometricRetry: Boolean = false,
    biometricReason: String = ""
) {
    if (!visible) return
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val context = LocalContext.current
    val activity = context as FragmentActivity
    var entered by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    var shake by remember { mutableStateOf(false) }
    val shakeOffset = remember { Animatable(0f) }
    val scope = rememberCoroutineScope()
    val biometricAvailable = remember { MeshBiometricAuth.isAvailable(activity) }
    val showBiometric = showsBiometricRetry && biometricAvailable && session.secureStorage.isBiometricEnabled()

    LaunchedEffect(shake) {
        if (shake) {
            repeat(4) {
                shakeOffset.animateTo(8f, tween(50))
                shakeOffset.animateTo(-8f, tween(50))
            }
            shakeOffset.animateTo(0f, tween(50))
            shake = false
        }
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = MeshColors.Background
    ) {
        MeshPasscodeEntryLayout(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = MeshMetrics.ScreenPadding),
            header = {
                Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Spacer(modifier = Modifier.weight(1f))
                    TextButton(onClick = onDismiss) {
                        Text(L10n.Common.cancel(context), color = MeshColors.TextSecondary)
                    }
                }
            }
        ) {
            Spacer(modifier = Modifier.height(12.dp))
            Text(title, style = MeshTypography.ScreenTitle, color = MeshColors.TextPrimary)
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                if (showBiometric) {
                    L10n.tr(context, "settings_view_recovery_subtitle_biometric", "Biometrics")
                } else {
                    subtitle
                },
                style = MeshTypography.Secondary,
                color = MeshColors.TextSecondary
            )
            error?.let {
                Spacer(modifier = Modifier.height(12.dp))
                Text(it, style = MeshTypography.Caption, color = MeshColors.Warning)
            }
            if (showBiometric) {
                Spacer(modifier = Modifier.height(16.dp))
                MeshPrimaryButton(
                    title = L10n.tr(context, "security_lock_faceid", "Biometrics"),
                    onClick = {
                        scope.launch {
                            when (MeshBiometricAuth.authenticate(activity, biometricReason.ifBlank { title })) {
                                MeshBiometricAuth.AuthResult.SUCCESS -> onVerified()
                                MeshBiometricAuth.AuthResult.CANCELLED -> Unit
                                else -> error = L10n.tr(context, "security_passcode_incorrect")
                            }
                        }
                    }
                )
            }
            Spacer(modifier = Modifier.height(24.dp))
            MeshPasscodeDots(
                enteredCount = entered.length,
                modifier = Modifier
                    .align(Alignment.CenterHorizontally)
                    .offset { IntOffset(shakeOffset.value.roundToInt(), 0) }
            )
            Spacer(modifier = Modifier.weight(1f))
            MeshPasscodeKeypad(
                onDigit = { digit ->
                    if (entered.length < SecureStorage.PASSCODE_LENGTH) {
                        entered += digit
                        error = null
                        if (entered.length == SecureStorage.PASSCODE_LENGTH) {
                            if (session.secureStorage.verifyPasscode(entered)) {
                                entered = ""
                                onVerified()
                            } else {
                                error = L10n.tr(context, "security_passcode_incorrect")
                                entered = ""
                                shake = true
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
}
