package com.mesh.wallet.data

import android.content.Context
import com.mesh.wallet.data.secure.SecureStorage
import com.mesh.wallet.data.secure.WalletRegistry
import com.mesh.wallet.data.tron.TronWalletException
import com.mesh.wallet.data.tron.TronWalletService
import com.mesh.wallet.domain.model.PendingWalletDraft
import com.mesh.wallet.domain.model.WalletImportKind

class MeshWalletService(
    private val context: Context,
    private val registry: WalletRegistry,
    private val secureStorage: SecureStorage
) {
    data class CreationResult(
        val words: List<String>,
        val address: String
    )

    fun generateWallet(): CreationResult {
        val (words, snapshot) = TronWalletService.createWallet()
        return CreationResult(words = words, address = snapshot.address)
    }

    fun importWallet(words: List<String>): String {
        return TronWalletService.importWallet(words).address
    }

    fun importPrivateKey(hex: String): String {
        return TronWalletService.importPrivateKey(hex).address
    }

    fun activateWallet(words: List<String>, name: String? = null): String {
        val address = importWallet(words)
        val walletId = registry.registerMnemonicWallet(words, address, name)
        secureStorage.saveMnemonic(walletId, words)
        return address
    }

    fun activateWallet(privateKeyHex: String, expectedAddress: String, name: String? = null): String {
        val normalized = TronWalletService.normalizePrivateKeyHex(privateKeyHex)
            .joinToString("") { "%02x".format(it) }
        val address = importPrivateKey(normalized)
        require(address == expectedAddress.trim()) { "Derived address does not match." }
        val walletId = registry.registerPrivateKeyWallet(address, name)
        secureStorage.savePrivateKey(walletId, normalized)
        return address
    }

    fun commitDraft(draft: PendingWalletDraft, name: String? = null): String {
        return when (draft.importKind) {
            WalletImportKind.MNEMONIC -> {
                val words = draft.words ?: error("Missing mnemonic")
                activateWallet(words, name)
            }
            WalletImportKind.PRIVATE_KEY -> {
                val key = draft.privateKeyHex ?: error("Missing private key")
                val address = draft.address ?: importPrivateKey(key)
                activateWallet(key, address, name)
            }
        }
    }

    fun removeWallet(walletId: String) {
        secureStorage.deleteWalletSecrets(walletId)
        registry.removeWallet(walletId)
        if (!registry.hasAnyWallet) {
            secureStorage.clearPasscode()
        }
    }

    fun loadMnemonic(walletId: String): List<String>? = secureStorage.loadMnemonic(walletId)

    companion object {
        fun create(context: Context): MeshWalletService {
            val registry = WalletRegistry(context)
            val secure = SecureStorage(context)
            return MeshWalletService(context, registry, secure)
        }
    }
}
