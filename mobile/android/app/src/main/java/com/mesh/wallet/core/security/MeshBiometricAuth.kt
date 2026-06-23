package com.mesh.wallet.core.security

import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import kotlin.coroutines.resume
import kotlinx.coroutines.suspendCancellableCoroutine

object MeshBiometricAuth {
    enum class BiometricKind { FACE, FINGERPRINT, NONE }
    enum class AuthResult { SUCCESS, CANCELLED, UNAVAILABLE, LOCKOUT, FAILED }

    fun kind(context: android.content.Context): BiometricKind {
        val manager = BiometricManager.from(context)
        return when (manager.canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG)) {
            BiometricManager.BIOMETRIC_SUCCESS -> {
                // Best-effort — Android doesn't expose Face vs Fingerprint cleanly
                BiometricKind.FINGERPRINT
            }
            else -> BiometricKind.NONE
        }
    }

    fun isAvailable(context: android.content.Context): Boolean =
        BiometricManager.from(context).canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG) ==
            BiometricManager.BIOMETRIC_SUCCESS

    fun displayName(context: android.content.Context): String =
        if (kind(context) != BiometricKind.NONE) "Biometrics" else "Biometrics"

    suspend fun authenticate(activity: FragmentActivity, reason: String): AuthResult =
        suspendCancellableCoroutine { cont ->
            if (!isAvailable(activity)) {
                cont.resume(AuthResult.UNAVAILABLE)
                return@suspendCancellableCoroutine
            }
            val executor = ContextCompat.getMainExecutor(activity)
            val prompt = BiometricPrompt(
                activity,
                executor,
                object : BiometricPrompt.AuthenticationCallback() {
                    override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                        cont.resume(AuthResult.SUCCESS)
                    }
                    override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                        cont.resume(
                            when (errorCode) {
                                BiometricPrompt.ERROR_USER_CANCELED,
                                BiometricPrompt.ERROR_NEGATIVE_BUTTON,
                                BiometricPrompt.ERROR_CANCELED -> AuthResult.CANCELLED
                                BiometricPrompt.ERROR_LOCKOUT,
                                BiometricPrompt.ERROR_LOCKOUT_PERMANENT -> AuthResult.LOCKOUT
                                else -> AuthResult.FAILED
                            }
                        )
                    }
                    override fun onAuthenticationFailed() {}
                }
            )
            prompt.authenticate(
                BiometricPrompt.PromptInfo.Builder()
                    .setTitle(reason)
                    .setNegativeButtonText("Cancel")
                    .setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_STRONG)
                    .build()
            )
        }
}
