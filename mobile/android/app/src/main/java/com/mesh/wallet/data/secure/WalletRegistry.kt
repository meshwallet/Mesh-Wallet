package com.mesh.wallet.data.secure

import android.content.Context
import androidx.core.content.edit
import com.mesh.wallet.domain.model.StoredWallet
import com.mesh.wallet.domain.model.WalletImportKind
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.util.UUID

class WalletRegistry(context: Context) {
    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val json = Json { ignoreUnknownKeys = true }

    val wallets: List<StoredWallet>
        get() = loadWallets()

    val activeWalletId: String?
        get() {
            val id = prefs.getString(KEY_ACTIVE_ID, null)?.trim().orEmpty()
            if (id.isNotEmpty() && loadWallets().any { it.id == id }) return id
            return loadWallets().firstOrNull()?.id
        }

    val hasAnyWallet: Boolean get() = loadWallets().isNotEmpty()

    fun wallet(id: String): StoredWallet? = loadWallets().firstOrNull { it.id == id }

    fun setActiveWallet(id: String) {
        if (loadWallets().none { it.id == id }) return
        prefs.edit {
            putString(KEY_ACTIVE_ID, id)
            putBoolean(KEY_ACTIVATED, true)
            wallet(id)?.let { putString(KEY_LEGACY_ADDRESS, it.address) }
        }
    }

    fun registerMnemonicWallet(words: List<String>, address: String, name: String?): String {
        val wallet = StoredWallet(
            id = UUID.randomUUID().toString(),
            name = name?.trim().orEmpty().ifEmpty { defaultName() },
            address = address,
            importKind = WalletImportKind.MNEMONIC
        )
        appendWallet(wallet)
        return wallet.id
    }

    fun registerPrivateKeyWallet(address: String, name: String?): String {
        val wallet = StoredWallet(
            id = UUID.randomUUID().toString(),
            name = name?.trim().orEmpty().ifEmpty { defaultName() },
            address = address,
            importKind = WalletImportKind.PRIVATE_KEY
        )
        appendWallet(wallet)
        return wallet.id
    }

    fun renameWallet(id: String, newName: String) {
        val updated = loadWallets().map { wallet ->
            if (wallet.id == id) wallet.copy(name = newName.trim()) else wallet
        }
        saveWallets(updated)
    }

    fun removeWallet(id: String) {
        val remaining = loadWallets().filterNot { it.id == id }
        saveWallets(remaining)
        if (prefs.getString(KEY_ACTIVE_ID, null) == id) {
            prefs.edit {
                if (remaining.isEmpty()) {
                    remove(KEY_ACTIVE_ID)
                    remove(KEY_ACTIVATED)
                    remove(KEY_LEGACY_ADDRESS)
                } else {
                    putString(KEY_ACTIVE_ID, remaining.first().id)
                    putString(KEY_LEGACY_ADDRESS, remaining.first().address)
                }
            }
        }
    }

    fun isOnboardingComplete(): Boolean = prefs.getBoolean(KEY_ONBOARDING_COMPLETE, false)

    fun markOnboardingComplete() {
        prefs.edit { putBoolean(KEY_ONBOARDING_COMPLETE, true) }
    }

    private fun appendWallet(wallet: StoredWallet) {
        val list = loadWallets().toMutableList()
        list.add(wallet)
        saveWallets(list)
        setActiveWallet(wallet.id)
    }

    private fun loadWallets(): List<StoredWallet> {
        val raw = prefs.getString(KEY_WALLETS, null) ?: return emptyList()
        return runCatching { json.decodeFromString<List<StoredWallet>>(raw) }.getOrDefault(emptyList())
    }

    private fun saveWallets(wallets: List<StoredWallet>) {
        prefs.edit { putString(KEY_WALLETS, json.encodeToString(wallets)) }
    }

    private fun defaultName(): String = suggestedName()

    fun suggestedName(): String {
        val count = loadWallets().size
        return if (count == 0) "Main wallet" else "Wallet ${count + 1}"
    }

    fun isWalletNameTaken(name: String, excludingWalletId: String? = null): Boolean {
        val normalized = name.trim().lowercase()
        if (normalized.isEmpty()) return false
        return loadWallets().any { wallet ->
            wallet.id != excludingWalletId && wallet.name.trim().lowercase() == normalized
        }
    }

    companion object {
        private const val PREFS_NAME = "mesh_wallet_registry"
        private const val KEY_WALLETS = "wallets.list"
        private const val KEY_ACTIVE_ID = "wallets.activeId"
        private const val KEY_ACTIVATED = "wallet.activated"
        private const val KEY_LEGACY_ADDRESS = "wallet.address"
        private const val KEY_ONBOARDING_COMPLETE = "onboarding.complete"
    }
}
