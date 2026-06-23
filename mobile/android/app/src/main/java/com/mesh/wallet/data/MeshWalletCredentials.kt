package com.mesh.wallet.data

import com.mesh.wallet.data.secure.SecureStorage
import com.mesh.wallet.data.secure.WalletRegistry
import com.mesh.wallet.data.tron.TronApiException
import com.mesh.wallet.data.tron.TronWalletService
import com.mesh.wallet.domain.model.WalletImportKind
import wallet.core.jni.CoinType
import wallet.core.jni.HDWallet

class MeshWalletCredentials(
    private val registry: WalletRegistry,
    private val secureStorage: SecureStorage
) {
    data class Resolved(
        val walletId: String,
        val address: String,
        val importKind: WalletImportKind,
        val privateKey: ByteArray,
        val mnemonic: List<String>?,
        val derivationPath: String
    )

    fun resolve(walletId: String? = registry.activeWalletId): Resolved {
        val id = walletId ?: registry.activeWalletId
            ?: throw TronApiException.BroadcastFailed("Wallet is not initialized")
        val wallet = registry.wallet(id)
            ?: throw TronApiException.BroadcastFailed("Wallet is not initialized")

        return when (wallet.importKind) {
            WalletImportKind.MNEMONIC -> {
                val words = secureStorage.loadMnemonic(id)
                    ?: throw TronApiException.BroadcastFailed("Wallet is not initialized")
                val snapshot = TronWalletService.importWallet(words)
                require(snapshot.address == wallet.address) {
                    throw TronApiException.BroadcastFailed("Wallet address mismatch.")
                }
                val path = com.mesh.wallet.core.config.TronConfiguration.DEFAULT_DERIVATION_PATH
                val key = signingKeyFromMnemonic(words, path)
                Resolved(id, wallet.address, WalletImportKind.MNEMONIC, key, words, path)
            }
            WalletImportKind.PRIVATE_KEY -> {
                val hex = secureStorage.loadPrivateKey(id)
                    ?: throw TronApiException.BroadcastFailed("Wallet is not initialized")
                val key = TronWalletService.normalizePrivateKeyHex(hex)
                val derived = TronWalletService.importPrivateKey(hex).address
                require(derived == wallet.address) {
                    throw TronApiException.BroadcastFailed("Wallet address mismatch.")
                }
                Resolved(id, wallet.address, WalletImportKind.PRIVATE_KEY, key, null, "")
            }
        }
    }

    fun supportsHdWalletFeatures(walletId: String? = registry.activeWalletId): Boolean {
        val id = walletId ?: return false
        return registry.wallet(id)?.importKind == WalletImportKind.MNEMONIC
    }

    fun signingKey(walletId: String? = null, derivationPath: String? = null): ByteArray {
        val resolved = resolve(walletId)
        if (derivationPath.isNullOrBlank() || derivationPath == resolved.derivationPath) {
            return resolved.privateKey
        }
        val words = resolved.mnemonic
            ?: throw TronApiException.BroadcastFailed("This wallet cannot sign from a derived address.")
        return signingKeyFromMnemonic(words, derivationPath)
    }

    private fun signingKeyFromMnemonic(words: List<String>, path: String): ByteArray {
        val mnemonic = words.joinToString(" ")
        val hdWallet = HDWallet(mnemonic, "")
            ?: throw TronApiException.BroadcastFailed("Invalid mnemonic")
        return hdWallet.getKey(CoinType.TRON, path).data()
    }
}
