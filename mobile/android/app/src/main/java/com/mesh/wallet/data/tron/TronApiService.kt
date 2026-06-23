package com.mesh.wallet.data.tron

import com.mesh.wallet.core.config.TronConfiguration
import com.mesh.wallet.domain.model.TransactionDirection
import com.mesh.wallet.domain.model.WalletTransaction
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.math.BigDecimal
import java.math.RoundingMode

data class TronAccountResources(
    val energyRemaining: Long = 0,
    val bandwidthRemaining: Long = 0,
    val hasEnoughTrxForFees: Boolean = false
)

object TronApiService {
    private val json = Json { ignoreUnknownKeys = true }

    suspend fun fetchUsdtBalance(address: String): BigDecimal? {
        return fetchUsdtBalanceFromTrc20(address) ?: fetchUsdtBalanceFromAccount(address)
    }

    suspend fun fetchAccountBalance(address: String): com.mesh.wallet.domain.model.TronAccountBalance {
        val trx = fetchTrxBalance(address)
        val usdt = fetchUsdtBalance(address) ?: BigDecimal.ZERO
        val txCount = fetchTransactionCount(address)
        return com.mesh.wallet.domain.model.TronAccountBalance(
            trxBalance = trx,
            usdtBalance = usdt,
            transactionCount = txCount
        )
    }

    suspend fun isAccountActivated(address: String): Boolean {
        return runCatching {
            val raw = TronApiClient.post("/wallet/getaccount", TronApiClient.accountBody(address))
            val response = json.decodeFromString<AccountResponse>(raw)
            response.createTime != null
        }.getOrDefault(true)
    }

    suspend fun fetchAccountResources(address: String): TronAccountResources {
        val raw = TronApiClient.post(
            "/wallet/getaccountresource",
            TronApiClient.accountBody(address)
        )
        val decoded = json.decodeFromString<AccountResourceResponse>(raw)
        val energy = (decoded.energyLimit ?: 0L) - (decoded.energyUsed ?: 0L)
        val freeNet = (decoded.freeNetLimit ?: 0L) - (decoded.freeNetUsed ?: 0L)
        val net = (decoded.netLimit ?: 0L) - (decoded.netUsed ?: 0L)
        val bandwidth = maxOf(freeNet, net)
        val trx = fetchTrxBalance(address)
        return TronAccountResources(
            energyRemaining = maxOf(energy, 0),
            bandwidthRemaining = maxOf(bandwidth, 0),
            hasEnoughTrxForFees = trx >= 1.0 || energy > 0
        )
    }

    suspend fun fetchUsdtTransactions(address: String, limit: Int = 20): List<WalletTransaction> {
        val raw = TronApiClient.get(
            path = "/v1/accounts/$address/transactions/trc20",
            query = mapOf(
                "limit" to limit.toString(),
                "contract_address" to TronConfiguration.usdtContractAddress,
                "only_confirmed" to "true"
            )
        )
        val decoded = json.decodeFromString<Trc20HistoryResponse>(raw)
        return decoded.data.mapNotNull { item -> mapHistoryItem(item, address) }
    }

    private suspend fun fetchTrxBalance(address: String): Double {
        val raw = TronApiClient.post("/wallet/getaccount", TronApiClient.accountBody(address))
        val response = json.decodeFromString<AccountResponse>(raw)
        val sun = response.balance ?: 0L
        return sun / 1_000_000.0
    }

    private suspend fun fetchTransactionCount(address: String): Int {
        return runCatching {
            val raw = TronApiClient.get("/v1/accounts/$address")
            json.decodeFromString<AccountListResponse>(raw).data.firstOrNull()?.transactions ?: 0
        }.getOrDefault(0)
    }

    private suspend fun fetchUsdtBalanceFromTrc20(address: String): BigDecimal? {
        return runCatching {
            val raw = TronApiClient.get(
                path = "/v1/accounts/$address/trc20/balance",
                query = mapOf(
                    "contract_address" to TronConfiguration.usdtContractAddress,
                    "limit" to "1"
                )
            )
            val decoded = json.decodeFromString<Trc20BalanceResponse>(raw)
            val tokenValue = decoded.data.firstOrNull()?.get(TronConfiguration.usdtContractAddress)
            parseUsdt(tokenValue ?: "0")
        }.getOrNull()
    }

    private suspend fun fetchUsdtBalanceFromAccount(address: String): BigDecimal? {
        return runCatching {
            val raw = TronApiClient.get("/v1/accounts/$address")
            val decoded = json.decodeFromString<AccountListResponse>(raw)
            for (token in decoded.data.firstOrNull()?.trc20.orEmpty()) {
                val value = token[TronConfiguration.usdtContractAddress]
                if (value != null) return parseUsdt(value)
            }
            BigDecimal.ZERO
        }.getOrNull()
    }

    private fun parseUsdt(raw: String): BigDecimal {
        val value = raw.toBigDecimalOrNull() ?: BigDecimal.ZERO
        return value.divide(BigDecimal.TEN.pow(TronConfiguration.TOKEN_DECIMALS), 6, RoundingMode.HALF_UP)
    }

    private fun mapHistoryItem(item: Trc20HistoryItem, walletAddress: String): WalletTransaction? {
        val amount = parseUsdt(item.value ?: return null)
        if (amount <= BigDecimal.ZERO) return null
        val from = item.from ?: return null
        val to = item.to ?: return null
        val direction = if (from.equals(walletAddress, ignoreCase = true)) {
            TransactionDirection.OUTGOING
        } else {
            TransactionDirection.INCOMING
        }
        val counterparty = if (direction == TransactionDirection.OUTGOING) to else from
        return WalletTransaction(
            id = item.transactionId ?: item.eventIndex?.toString() ?: return null,
            txId = item.transactionId,
            direction = direction,
            amount = amount,
            counterpartyAddress = counterparty,
            timestamp = item.blockTimestamp ?: System.currentTimeMillis()
        )
    }
}

@Serializable
private data class AccountResponse(
    val balance: Long? = null,
    @SerialName("create_time") val createTime: Long? = null
)

@Serializable
private data class AccountResourceResponse(
    @SerialName("EnergyLimit") val energyLimit: Long? = null,
    @SerialName("EnergyUsed") val energyUsed: Long? = null,
    @SerialName("freeNetLimit") val freeNetLimit: Long? = null,
    @SerialName("freeNetUsed") val freeNetUsed: Long? = null,
    @SerialName("NetLimit") val netLimit: Long? = null,
    @SerialName("NetUsed") val netUsed: Long? = null
)

@Serializable
private data class AccountListResponse(val data: List<AccountData> = emptyList())

@Serializable
private data class AccountData(
    val transactions: Int? = null,
    val trc20: List<Map<String, String>>? = null
)

@Serializable
private data class Trc20BalanceResponse(val data: List<Map<String, String>> = emptyList())

@Serializable
private data class Trc20HistoryResponse(val data: List<Trc20HistoryItem> = emptyList())

@Serializable
private data class Trc20HistoryItem(
    @SerialName("transaction_id") val transactionId: String? = null,
    val from: String? = null,
    val to: String? = null,
    val value: String? = null,
    @SerialName("block_timestamp") val blockTimestamp: Long? = null,
    @SerialName("event_index") val eventIndex: Int? = null
)
