package com.mesh.wallet.data.secure

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import java.security.MessageDigest
import java.security.SecureRandom

class SecureStorage(context: Context) {
    private val masterKey = MasterKey.Builder(context)
        .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
        .build()

    private val prefs: SharedPreferences = EncryptedSharedPreferences.create(
        context,
        "mesh_secure_prefs",
        masterKey,
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
    )

    fun saveMnemonic(walletId: String, words: List<String>) {
        prefs.edit().putString(mnemonicKey(walletId), words.joinToString(" ")).apply()
    }

    fun loadMnemonic(walletId: String): List<String>? =
        prefs.getString(mnemonicKey(walletId), null)
            ?.split(" ")
            ?.filter { it.isNotBlank() }
            ?.takeIf { it.isNotEmpty() }

    fun savePrivateKey(walletId: String, hex: String) {
        prefs.edit().putString(privateKeyKey(walletId), hex).apply()
    }

    fun loadPrivateKey(walletId: String): String? =
        prefs.getString(privateKeyKey(walletId), null)

    fun deleteWalletSecrets(walletId: String) {
        prefs.edit()
            .remove(mnemonicKey(walletId))
            .remove(privateKeyKey(walletId))
            .apply()
    }

    fun setPasscode(passcode: String): Boolean {
        if (passcode.length != PASSCODE_LENGTH || !passcode.all { it.isDigit() }) return false
        val salt = ByteArray(32).also { SecureRandom().nextBytes(it) }
        val hash = hashPasscode(passcode, salt)
        prefs.edit()
            .putBoolean(KEY_PASSCODE_ENABLED, true)
            .putString(KEY_PASSCODE_HASH, hash.toHex())
            .putString(KEY_PASSCODE_SALT, salt.toHex())
            .apply()
        return true
    }

    fun verifyPasscode(passcode: String): Boolean {
        val storedHash = prefs.getString(KEY_PASSCODE_HASH, null) ?: return false
        val saltHex = prefs.getString(KEY_PASSCODE_SALT, null) ?: return false
        val salt = saltHex.hexToBytes()
        return hashPasscode(passcode, salt).toHex() == storedHash
    }

    fun isPasscodeEnabled(): Boolean =
        prefs.getBoolean(KEY_PASSCODE_ENABLED, false) && prefs.getString(KEY_PASSCODE_HASH, null) != null

    fun setBiometricEnabled(enabled: Boolean) {
        prefs.edit().putBoolean(KEY_BIOMETRIC_ENABLED, enabled).apply()
    }

    fun isBiometricEnabled(): Boolean =
        prefs.getBoolean(KEY_BIOMETRIC_ENABLED, false) && isPasscodeEnabled()

    fun clearPasscode() {
        prefs.edit()
            .remove(KEY_PASSCODE_ENABLED)
            .remove(KEY_PASSCODE_HASH)
            .remove(KEY_PASSCODE_SALT)
            .remove(KEY_BIOMETRIC_ENABLED)
            .apply()
    }

    private fun hashPasscode(passcode: String, salt: ByteArray): ByteArray {
        val digest = MessageDigest.getInstance("SHA-256")
        digest.update(salt)
        digest.update(passcode.toByteArray())
        return digest.digest()
    }

    private fun mnemonicKey(walletId: String) = "mnemonic.$walletId"
    private fun privateKeyKey(walletId: String) = "privatekey.$walletId"

    companion object {
        const val PASSCODE_LENGTH = 6
        private const val KEY_PASSCODE_ENABLED = "passcode.enabled"
        private const val KEY_PASSCODE_HASH = "passcode.hash"
        private const val KEY_PASSCODE_SALT = "passcode.salt"
        private const val KEY_BIOMETRIC_ENABLED = "passcode.biometric"
    }
}

private fun ByteArray.toHex(): String = joinToString("") { "%02x".format(it) }

private fun String.hexToBytes(): ByteArray {
    check(length % 2 == 0)
    return chunked(2).map { it.toInt(16).toByte() }.toByteArray()
}
