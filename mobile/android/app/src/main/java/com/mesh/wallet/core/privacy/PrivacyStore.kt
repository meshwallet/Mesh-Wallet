package com.mesh.wallet.core.privacy

import android.content.Context
import androidx.core.content.edit

class PrivacyStore(context: Context) {
    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun walletReceiveSlotCount(): Int = WALLET_RECEIVE_SLOT_COUNT

    fun ensureDefaultReceiveSetup(walletId: String) {
        registerReceiveIndex(walletId, 0)
        val countKey = key(ACTIVE_RECEIVE_COUNT, walletId)
        if (!prefs.contains(countKey)) setActiveReceiveAddressCount(walletId, 1)
        val nextKey = key(NEXT_RECEIVE_INDEX, walletId)
        if (prefs.getInt(nextKey, 0) < 1) prefs.edit { putInt(nextKey, 1) }
    }

    fun activeReceiveAddressCount(walletId: String): Int {
        ensureDefaultReceiveSetup(walletId)
        val stored = prefs.getInt(key(ACTIVE_RECEIVE_COUNT, walletId), 1)
        return stored.coerceIn(1, WALLET_RECEIVE_SLOT_COUNT)
    }

    fun setActiveReceiveAddressCount(walletId: String, count: Int) {
        prefs.edit { putInt(key(ACTIVE_RECEIVE_COUNT, walletId), count.coerceIn(1, WALLET_RECEIVE_SLOT_COUNT)) }
    }

    fun visibleReceiveSlotCount(walletId: String): Int = visibleReceiveSlotIndices(walletId).size

    fun visibleReceiveSlotIndices(walletId: String): List<Int> {
        val count = activeReceiveAddressCount(walletId)
        val hidden = hiddenReceiveSlotIndices(walletId)
        return (0 until count).filter { it !in hidden }
    }

    fun hiddenReceiveSlotIndices(walletId: String): Set<Int> {
        val raw = prefs.getStringSet(key(HIDDEN_SLOTS, walletId), emptySet()).orEmpty()
        return raw.mapNotNull { it.toIntOrNull() }.filter { it > 0 }.toSet()
    }

    fun addReceiveAddress(walletId: String): Int? {
        ensureDefaultReceiveSetup(walletId)
        val current = activeReceiveAddressCount(walletId)
        val hidden = hiddenReceiveSlotIndices(walletId).toMutableSet()
        val reused = (1 until current).firstOrNull { hidden.contains(it) }
        if (reused != null) {
            hidden.remove(reused)
            setHiddenReceiveSlotIndices(walletId, hidden)
            registerReceiveIndex(walletId, reused)
            return reused
        }
        if (current >= WALLET_RECEIVE_SLOT_COUNT) return null
        registerReceiveIndex(walletId, current)
        setActiveReceiveAddressCount(walletId, current + 1)
        return current
    }

    fun removeReceiveAddress(walletId: String, index: Int): Boolean {
        if (index <= 0) return false
        val current = activeReceiveAddressCount(walletId)
        if (index >= current) return false
        val hidden = hiddenReceiveSlotIndices(walletId).toMutableSet()
        if (hidden.contains(index)) return false
        hidden.add(index)
        setHiddenReceiveSlotIndices(walletId, hidden)
        setReceiveSlotName(walletId, index, null)
        if (selectedReceiveSlotIndex(walletId) == index) setSelectedReceiveSlotIndex(walletId, 0)
        return true
    }

    fun selectedReceiveSlotIndex(walletId: String): Int {
        val visible = visibleReceiveSlotIndices(walletId)
        if (visible.isEmpty()) return 0
        val stored = prefs.getInt(key(SELECTED_RECEIVE_SLOT, walletId), 0)
        return if (stored in visible) stored else visible.last()
    }

    fun selectedSendSlotIndex(walletId: String): Int {
        val visible = visibleReceiveSlotIndices(walletId)
        if (visible.isEmpty()) return 0
        val stored = prefs.getInt(key(SELECTED_SEND_SLOT, walletId), 0)
        return if (stored in visible) stored else visible.last()
    }

    fun setSelectedReceiveSlotIndex(walletId: String, index: Int) {
        val visible = visibleReceiveSlotIndices(walletId)
        val resolved = if (index in visible) index else visible.lastOrNull() ?: 0
        prefs.edit { putInt(key(SELECTED_RECEIVE_SLOT, walletId), resolved) }
        prefs.edit { putInt(key(SELECTED_SEND_SLOT, walletId), resolved) }
    }

    fun setSelectedSendSlotIndex(walletId: String, index: Int) {
        val visible = visibleReceiveSlotIndices(walletId)
        val resolved = if (index in visible) index else visible.lastOrNull() ?: 0
        prefs.edit { putInt(key(SELECTED_SEND_SLOT, walletId), resolved) }
    }

    fun slotName(walletId: String, index: Int): String {
        val custom = prefs.getString(key(SLOT_NAME, walletId, index), null)
        return custom ?: defaultSlotName(index)
    }

    fun setReceiveSlotName(walletId: String, index: Int, name: String?) {
        val editor = prefs.edit()
        val k = key(SLOT_NAME, walletId, index)
        if (name.isNullOrBlank()) editor.remove(k) else editor.putString(k, name.trim())
        editor.apply()
    }

    fun registerReceiveIndex(walletId: String, index: Int) {
        val indices = registeredReceiveIndices(walletId).toMutableSet()
        indices.add(index)
        prefs.edit {
            putStringSet(key(REGISTERED_INDICES, walletId), indices.map { it.toString() }.toSet())
        }
    }

    fun registeredReceiveIndices(walletId: String): Set<Int> {
        val raw = prefs.getStringSet(key(REGISTERED_INDICES, walletId), setOf("0")).orEmpty()
        return raw.mapNotNull { it.toIntOrNull() }.toSet().ifEmpty { setOf(0) }
    }

    fun clearWalletData(walletId: String) {
        val keys = prefs.all.keys.filter { it.contains(walletId) }
        prefs.edit { keys.forEach { remove(it) } }
    }

    private fun setHiddenReceiveSlotIndices(walletId: String, indices: Set<Int>) {
        prefs.edit {
            if (indices.isEmpty()) remove(key(HIDDEN_SLOTS, walletId))
            else putStringSet(key(HIDDEN_SLOTS, walletId), indices.map { it.toString() }.toSet())
        }
    }

    private fun defaultSlotName(index: Int): String =
        if (index == 0) "Main account" else "Address ${index + 1}"

    private fun key(suffix: String, walletId: String, index: Int? = null): String =
        if (index == null) "privacy.$suffix.$walletId" else "privacy.$suffix.$walletId.$index"

    companion object {
        const val WALLET_RECEIVE_SLOT_COUNT = 5
        const val DEEP_RECOVERY_SCAN_COUNT = 1024
        private const val PREFS_NAME = "mesh_privacy"
        private const val ACTIVE_RECEIVE_COUNT = "activeReceiveCount"
        private const val HIDDEN_SLOTS = "hiddenSlots"
        private const val SELECTED_RECEIVE_SLOT = "selectedReceiveSlot"
        private const val SELECTED_SEND_SLOT = "selectedSendSlot"
        private const val SLOT_NAME = "slotName"
        private const val REGISTERED_INDICES = "registeredIndices"
        private const val NEXT_RECEIVE_INDEX = "nextReceiveIndex"
    }
}
