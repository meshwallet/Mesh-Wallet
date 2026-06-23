package com.mesh.wallet.ui.onboarding

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.mesh.wallet.core.session.WalletSession
import com.mesh.wallet.data.MeshWalletRestore
import com.mesh.wallet.domain.model.PendingWalletDraft
import com.mesh.wallet.domain.model.WalletImportKind
import com.mesh.wallet.domain.model.WalletPhraseFlow
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class OnboardingViewModel(
    private val session: WalletSession
) : ViewModel() {
    private val _draft = MutableStateFlow(PendingWalletDraft())
    val draft: StateFlow<PendingWalletDraft> = _draft.asStateFlow()

    var pendingPasscode: String = ""
        private set

    private val _isGenerating = MutableStateFlow(false)
    val isGenerating: StateFlow<Boolean> = _isGenerating.asStateFlow()

    private val _isImporting = MutableStateFlow(false)
    val isImporting: StateFlow<Boolean> = _isImporting.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    fun generateWallet(onSuccess: () -> Unit) {
        viewModelScope.launch {
            _isGenerating.value = true
            _error.value = null
            runCatching {
                val result = session.walletService.generateWallet()
                _draft.value = PendingWalletDraft(
                    words = result.words,
                    address = result.address,
                    importKind = WalletImportKind.MNEMONIC,
                    flow = WalletPhraseFlow.CREATED
                )
            }.onFailure {
                _error.value = it.message
            }
            _isGenerating.value = false
            if (_error.value == null) onSuccess()
        }
    }

    fun restoreFromPhrase(text: String, walletName: String, onSuccess: () -> Unit) {
        viewModelScope.launch {
            _isImporting.value = true
            _error.value = null
            runCatching {
                val trimmedName = walletName.trim()
                if (trimmedName.isNotEmpty() && session.registry.isWalletNameTaken(trimmedName)) {
                    throw IllegalStateException(WALLET_NAME_TAKEN)
                }
                val words = MeshWalletRestore.normalizePhrase(text)
                val address = withContext(Dispatchers.Default) {
                    session.walletService.importWallet(words)
                }
                _draft.value = PendingWalletDraft(
                    words = words,
                    address = address,
                    walletName = trimmedName.ifEmpty { null },
                    importKind = WalletImportKind.MNEMONIC,
                    flow = WalletPhraseFlow.RESTORED
                )
            }.onFailure {
                _error.value = when (it.message) {
                    WALLET_NAME_TAKEN -> WALLET_NAME_TAKEN
                    else -> it.message ?: "Invalid recovery phrase."
                }
            }
            _isImporting.value = false
            if (_error.value == null) onSuccess()
        }
    }

    fun restoreFromPrivateKey(text: String, walletName: String, onSuccess: () -> Unit) {
        viewModelScope.launch {
            _isImporting.value = true
            _error.value = null
            runCatching {
                val trimmedName = walletName.trim()
                if (trimmedName.isNotEmpty() && session.registry.isWalletNameTaken(trimmedName)) {
                    throw IllegalStateException(WALLET_NAME_TAKEN)
                }
                val normalized = MeshWalletRestore.normalizePrivateKeyInput(text)
                val address = withContext(Dispatchers.Default) {
                    session.walletService.importPrivateKey(normalized)
                }
                _draft.value = PendingWalletDraft(
                    privateKeyHex = normalized,
                    address = address,
                    walletName = trimmedName.ifEmpty { null },
                    importKind = WalletImportKind.PRIVATE_KEY,
                    flow = WalletPhraseFlow.RESTORED
                )
            }.onFailure {
                _error.value = when (it.message) {
                    WALLET_NAME_TAKEN -> WALLET_NAME_TAKEN
                    else -> it.message ?: "Invalid private key."
                }
            }
            _isImporting.value = false
            if (_error.value == null) onSuccess()
        }
    }

    fun setPendingPasscode(passcode: String) {
        pendingPasscode = passcode
    }

    fun commitPasscode() {
        session.secureStorage.setPasscode(pendingPasscode)
    }

    fun commitWallet() {
        val current = _draft.value
        session.walletService.commitDraft(current, current.walletName)
        session.reconcile()
    }

    companion object {
        const val WALLET_NAME_TAKEN = "A wallet with this name already exists."

        fun factory(session: WalletSession): ViewModelProvider.Factory =
            object : ViewModelProvider.Factory {
                @Suppress("UNCHECKED_CAST")
                override fun <T : ViewModel> create(modelClass: Class<T>): T {
                    return OnboardingViewModel(session) as T
                }
            }
    }
}
