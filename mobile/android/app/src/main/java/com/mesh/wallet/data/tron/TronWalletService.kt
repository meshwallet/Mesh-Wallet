package com.mesh.wallet.data.tron

import com.mesh.wallet.core.config.TronConfiguration
import wallet.core.jni.CoinType
import wallet.core.jni.HDWallet
import wallet.core.jni.PrivateKey

data class TronWalletSnapshot(
    val address: String,
    val derivationPath: String
)

object TronWalletService {
    fun createWallet(passphrase: String = ""): Pair<List<String>, TronWalletSnapshot> {
        val wallet = HDWallet(128, passphrase)
            ?: throw TronWalletException.WalletCreationFailed
        val words = wallet.mnemonic().split(" ").filter { it.isNotBlank() }
        val snapshot = snapshotFrom(wallet)
        return words to snapshot
    }

    fun importWallet(words: List<String>, passphrase: String = ""): TronWalletSnapshot {
        val mnemonic = words
            .map { it.trim().lowercase() }
            .filter { it.isNotEmpty() }
            .joinToString(" ")
        val wallet = HDWallet(mnemonic, passphrase)
            ?: throw TronWalletException.InvalidMnemonic
        return snapshotFrom(wallet)
    }

    fun deriveRelayAddress(accountIndex: Int, words: List<String>, passphrase: String = ""): String {
        val mnemonic = normalizedMnemonic(words)
        val wallet = HDWallet(mnemonic, passphrase)
            ?: throw TronWalletException.InvalidMnemonic
        val path = TronConfiguration.relayDerivationPath(accountIndex)
        val key = wallet.getKey(CoinType.TRON, path)
        return CoinType.TRON.deriveAddress(key)
    }

    fun deriveReceiveAddress(accountIndex: Int, words: List<String>, passphrase: String = ""): String {
        val mnemonic = normalizedMnemonic(words)
        val wallet = HDWallet(mnemonic, passphrase)
            ?: throw TronWalletException.InvalidMnemonic
        val path = TronConfiguration.receiveDerivationPath(accountIndex)
        val key = wallet.getKey(CoinType.TRON, path)
        return CoinType.TRON.deriveAddress(key)
    }

    fun importPrivateKey(hex: String): TronWalletSnapshot {
        val keyData = normalizePrivateKeyHex(hex)
        val privateKey = PrivateKey(keyData)
            ?: throw TronWalletException.InvalidPrivateKey
        val address = CoinType.TRON.deriveAddress(privateKey)
        if (address.isBlank()) throw TronWalletException.AddressDerivationFailed
        return TronWalletSnapshot(address = address, derivationPath = "")
    }

    fun isValidTronAddress(address: String): Boolean {
        val trimmed = address.trim()
        return trimmed.startsWith("T") && trimmed.length == 34
    }

    fun normalizePrivateKeyHex(input: String): ByteArray {
        var hex = input.trim()
            .removePrefix("0x")
            .removePrefix("0X")
            .filter { !it.isWhitespace() }
        require(hex.length == 64) { "Invalid private key length" }
        return hex.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
    }

    private fun snapshotFrom(wallet: HDWallet): TronWalletSnapshot {
        val address = wallet.getAddressForCoin(CoinType.TRON)
        if (address.isBlank()) throw TronWalletException.AddressDerivationFailed
        return TronWalletSnapshot(
            address = address,
            derivationPath = TronConfiguration.DEFAULT_DERIVATION_PATH
        )
    }

    private fun normalizedMnemonic(words: List<String>): String =
        words.map { it.trim().lowercase() }.filter { it.isNotEmpty() }.joinToString(" ")
}

sealed class TronWalletException(message: String) : Exception(message) {
    data object WalletCreationFailed : TronWalletException("Could not generate a new wallet.")
    data object InvalidMnemonic : TronWalletException("Invalid recovery phrase.")
    data object InvalidPrivateKey : TronWalletException("Invalid private key.")
    data object AddressDerivationFailed : TronWalletException("Could not derive Tron address.")
}
