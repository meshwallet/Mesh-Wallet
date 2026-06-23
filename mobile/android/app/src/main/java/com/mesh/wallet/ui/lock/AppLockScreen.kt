package com.mesh.wallet.ui.lock

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import kotlinx.coroutines.launch
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.fragment.app.FragmentActivity
import com.mesh.wallet.R
import com.mesh.wallet.core.security.MeshBiometricAuth
import com.mesh.wallet.core.session.WalletSession
import com.mesh.wallet.ui.components.MeshPrimaryButton
import com.mesh.wallet.data.secure.SecureStorage
import com.mesh.wallet.ui.components.MeshPasscodeDots
import com.mesh.wallet.ui.components.MeshPasscodeEntryLayout
import com.mesh.wallet.ui.components.MeshPasscodeKeypad
import com.mesh.wallet.ui.theme.MeshColors
import com.mesh.wallet.ui.theme.MeshMetrics
import com.mesh.wallet.ui.theme.MeshTypography

@Composable
fun AppLockScreen(
    session: WalletSession,
    onUnlocked: () -> Unit
) {
    val activity = LocalContext.current as FragmentActivity
    val scope = rememberCoroutineScope()
    var entered by remember { mutableStateOf("") }
    var error by remember { mutableStateOf(false) }
    val biometricAvailable = remember { MeshBiometricAuth.isAvailable(activity) }
    val biometricEnabled = session.secureStorage.isBiometricEnabled()

    LaunchedEffect(Unit) {
        if (biometricEnabled && biometricAvailable && !session.appLockController.didAttemptLaunchBiometric.value) {
            val unlocked = session.appLockController.attemptLaunchBiometricUnlock(activity)
            if (unlocked) onUnlocked()
        }
    }

    MeshPasscodeEntryLayout(
        modifier = Modifier
            .fillMaxSize()
            .background(MeshColors.Background)
            .padding(horizontal = MeshMetrics.ScreenPadding)
    ) {
        Spacer(modifier = Modifier.height(20.dp))
        Text(
            text = stringResource(R.string.security_lock_title),
            style = MeshTypography.ScreenTitle,
            color = MeshColors.TextPrimary
        )
        Spacer(modifier = Modifier.height(40.dp))
        MeshPasscodeDots(enteredCount = entered.length)
        if (error) {
            Spacer(modifier = Modifier.height(16.dp))
            Text(
                text = "Incorrect passcode",
                style = MeshTypography.Caption,
                color = MeshColors.Warning
            )
        }
        Spacer(modifier = Modifier.weight(1f))
        MeshPasscodeKeypad(
            onDigit = { digit ->
                if (entered.length < SecureStorage.PASSCODE_LENGTH) {
                    entered += digit
                    if (entered.length == SecureStorage.PASSCODE_LENGTH) {
                        if (session.secureStorage.verifyPasscode(entered)) {
                            session.appLockController.unlockForCurrentSession()
                            onUnlocked()
                        } else {
                            error = true
                            entered = ""
                        }
                    }
                }
            },
            onDelete = {
                error = false
                if (entered.isNotEmpty()) entered = entered.dropLast(1)
            }
        )
        if (biometricEnabled && biometricAvailable) {
            Spacer(modifier = Modifier.height(16.dp))
            MeshPrimaryButton(
                title = stringResource(R.string.security_lock_faceid, "Biometrics"),
                onClick = {
                    scope.launch {
                        val unlocked = session.appLockController.attemptLaunchBiometricUnlock(activity)
                        if (unlocked) {
                            session.appLockController.unlockForCurrentSession()
                            onUnlocked()
                        }
                    }
                }
            )
        }
        Spacer(modifier = Modifier.height(32.dp))
    }
}
