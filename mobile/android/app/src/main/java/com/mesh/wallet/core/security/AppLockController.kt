package com.mesh.wallet.core.security

import androidx.fragment.app.FragmentActivity
import com.mesh.wallet.core.session.WalletSession
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

class AppLockController(private val session: WalletSession) {
    private val _isUnlocked = MutableStateFlow(!needsLaunchLock())
    val isUnlocked: StateFlow<Boolean> = _isUnlocked.asStateFlow()

    private val _didAttemptLaunchBiometric = MutableStateFlow(false)
    val didAttemptLaunchBiometric: StateFlow<Boolean> = _didAttemptLaunchBiometric.asStateFlow()

    private var didEvaluateLaunchLock = needsLaunchLock()

    val shouldShowLock: Boolean
        get() = session.secureStorage.isPasscodeEnabled() && session.hasActiveWallet && !_isUnlocked.value

    fun unlock() {
        _isUnlocked.value = true
    }

    fun unlockForCurrentSession() {
        didEvaluateLaunchLock = true
        unlock()
    }

    suspend fun attemptLaunchBiometricUnlock(activity: FragmentActivity): Boolean {
        if (!shouldShowLock) return false
        if (!session.secureStorage.isBiometricEnabled()) return false
        if (!MeshBiometricAuth.isAvailable(activity)) return false

        _didAttemptLaunchBiometric.value = true
        val result = MeshBiometricAuth.authenticate(activity, "Unlock Mesh")
        if (result == MeshBiometricAuth.AuthResult.SUCCESS) {
            unlock()
            return true
        }
        return false
    }

    private fun needsLaunchLock(): Boolean =
        session.secureStorage.isPasscodeEnabled() && session.hasActiveWallet
}
