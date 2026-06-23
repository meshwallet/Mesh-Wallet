package com.mesh.wallet.core.send

import android.content.Context
import androidx.core.content.edit
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.math.BigDecimal
import java.util.UUID

@Serializable
data class PendingSendRecord(
    val id: String = UUID.randomUUID().toString(),
    val walletId: String,
    val recipientAddress: String,
    val amountText: String,
    val amountUsdt: String,
    val selectedSendSlotIndex: Int = 0,
    val fromAddress: String = "",
    val obligationId: String? = null,
    val presignedFeeTxJson: String? = null,
    val createdAt: Long = System.currentTimeMillis()
)

class MeshPendingSendStore(context: Context) {
    private val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private val json = Json { ignoreUnknownKeys = true }

    fun save(record: PendingSendRecord) {
        val all = loadAll().toMutableList()
        all.removeAll { it.id == record.id }
        all.add(record)
        persist(all)
    }

    fun remove(id: String) {
        persist(loadAll().filterNot { it.id == id })
    }

    fun loadAll(): List<PendingSendRecord> {
        val raw = prefs.getString(KEY_RECORDS, null) ?: return emptyList()
        return runCatching { json.decodeFromString<List<PendingSendRecord>>(raw) }.getOrDefault(emptyList())
    }

    fun loadForWallet(walletId: String): List<PendingSendRecord> =
        loadAll().filter { it.walletId == walletId }

    fun clear() {
        prefs.edit { remove(KEY_RECORDS) }
    }

    private fun persist(records: List<PendingSendRecord>) {
        prefs.edit { putString(KEY_RECORDS, json.encodeToString(records)) }
    }

    companion object {
        private const val PREFS = "mesh_pending_sends"
        private const val KEY_RECORDS = "records"
    }
}
