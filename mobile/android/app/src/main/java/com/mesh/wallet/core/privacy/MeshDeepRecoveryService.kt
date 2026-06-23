package com.mesh.wallet.core.privacy

import com.mesh.wallet.core.l10n.L10n
import com.mesh.wallet.core.network.SendErrorPresenter
import com.mesh.wallet.core.session.WalletSession
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class MeshDeepRecoveryService(private val session: WalletSession) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val _isRunning = MutableStateFlow(false)
    val isRunning: StateFlow<Boolean> = _isRunning.asStateFlow()

    private val _progressChecked = MutableStateFlow(0)
    val progressChecked: StateFlow<Int> = _progressChecked.asStateFlow()

    private val _progressTotal = MutableStateFlow(PrivacyStore.DEEP_RECOVERY_SCAN_COUNT)
    val progressTotal: StateFlow<Int> = _progressTotal.asStateFlow()

    private val _isTransferring = MutableStateFlow(false)
    val isTransferring: StateFlow<Boolean> = _isTransferring.asStateFlow()

    private val _statusMessage = MutableStateFlow<String?>(null)
    val statusMessage: StateFlow<String?> = _statusMessage.asStateFlow()

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = _errorMessage.asStateFlow()

    val progressFraction: Float
        get() = if (_progressTotal.value > 0) {
            (_progressChecked.value.toFloat() / _progressTotal.value).coerceAtMost(1f)
        } else 0f

    fun start(walletId: String? = session.registry.activeWalletId) {
        if (_isRunning.value) return
        val id = walletId ?: return
        _isRunning.value = true
        _errorMessage.value = null
        _statusMessage.value = null
        _isTransferring.value = false
        _progressChecked.value = 0
        _progressTotal.value = PrivacyStore.DEEP_RECOVERY_SCAN_COUNT

        scope.launch {
            try {
                val count = session.privacyService.recoverDeepFundsToMainWallet(id) { progress ->
                    when (progress) {
                        is com.mesh.wallet.data.privacy.MeshPrivacyService.DeepRecoveryProgress.Scanning -> {
                            _isTransferring.value = false
                            _progressChecked.value = progress.checked
                            _progressTotal.value = progress.total
                        }
                        is com.mesh.wallet.data.privacy.MeshPrivacyService.DeepRecoveryProgress.Transferring -> {
                            _isTransferring.value = true
                            _progressChecked.value = progress.current
                            _progressTotal.value = progress.total
                        }
                    }
                }
                _statusMessage.value = "Recovered $count address(es)"
                session.registry.activeWalletId?.let { session.backgroundSendService.refreshFeeStatus(it) }
                delay(2_500)
                _statusMessage.value = null
            } catch (e: CancellationException) {
                _errorMessage.value = null
            } catch (e: Exception) {
                _errorMessage.value = SendErrorPresenter.messageFor(e)
                _statusMessage.value = null
            } finally {
                _isRunning.value = false
                _isTransferring.value = false
            }
        }
    }

    fun cancel() {
        _isRunning.value = false
        _isTransferring.value = false
    }
}
