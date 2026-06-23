package com.mesh.wallet.core.session

import android.content.Context
import com.mesh.wallet.core.privacy.MeshDeepRecoveryService
import com.mesh.wallet.core.privacy.PrivacyStore
import com.mesh.wallet.core.security.AppLockController
import com.mesh.wallet.core.send.MeshBackgroundSendService
import com.mesh.wallet.core.send.MeshPendingSendStore
import com.mesh.wallet.data.MeshWalletCredentials
import com.mesh.wallet.data.MeshWalletService
import com.mesh.wallet.data.privacy.MeshPrivacyService
import com.mesh.wallet.data.secure.SecureStorage
import com.mesh.wallet.data.secure.WalletRegistry
import com.mesh.wallet.domain.model.StoredWallet
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

class WalletSession(context: Context) {
    val appContext: Context = context.applicationContext
    val registry = WalletRegistry(context)
    val secureStorage = SecureStorage(context)
    val walletService = MeshWalletService.create(context)
    val privacyStore = PrivacyStore(context)
    val pendingSendStore = MeshPendingSendStore(context)
    val credentials = MeshWalletCredentials(registry, secureStorage)
    val privacyService = MeshPrivacyService(registry, secureStorage, privacyStore, credentials)
    val backgroundSendService = MeshBackgroundSendService(
        credentials, privacyService, pendingSendStore
    )
    val appLockController = AppLockController(this)
    val deepRecoveryService = MeshDeepRecoveryService(this)

    private val _activeWallet = MutableStateFlow<StoredWallet?>(null)
    val activeWallet: StateFlow<StoredWallet?> = _activeWallet.asStateFlow()

    val hasActiveWallet: Boolean
        get() = registry.hasAnyWallet && registry.isOnboardingComplete()

    val requiresPasscodeOnLaunch: Boolean
        get() = secureStorage.isPasscodeEnabled() && hasActiveWallet

    fun reconcile() {
        val id = registry.activeWalletId
        _activeWallet.value = id?.let { registry.wallet(it) }
        id?.let { backgroundSendService.resumeProcessingSendsIfNeeded(it) }
    }

    fun setActiveWallet(id: String) {
        registry.setActiveWallet(id)
        reconcile()
    }

    fun markOnboardingComplete() {
        registry.markOnboardingComplete()
        reconcile()
    }

    fun completeOnboarding() {
        markOnboardingComplete()
    }
}
