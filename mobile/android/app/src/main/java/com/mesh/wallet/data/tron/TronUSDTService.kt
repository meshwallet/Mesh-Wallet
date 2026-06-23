package com.mesh.wallet.data.tron

import com.mesh.wallet.core.config.TronConfiguration
import java.math.BigDecimal
import java.math.RoundingMode
import java.text.DecimalFormat

object TronUSDTService {
    suspend fun fetchUsdtBalance(address: String): BigDecimal? =
        TronApiService.fetchUsdtBalance(address)

    suspend fun fetchTransactions(address: String, limit: Int = 20) =
        TronApiService.fetchUsdtTransactions(address, limit)

    suspend fun sendUsdt(
        signingKey: ByteArray,
        fromAddress: String,
        toAddress: String,
        amount: BigDecimal
    ): TronUsdtTransferResult = TronTransactionService.sendUsdt(
        signingKey = signingKey,
        fromAddress = fromAddress,
        toAddress = toAddress,
        amount = amount
    )

    fun isValidTronAddress(address: String): Boolean = TronWalletService.isValidTronAddress(address)

    fun formatUsdtAmount(amount: BigDecimal, includeSymbol: Boolean = true): String {
        val formatter = DecimalFormat("#,##0.00")
        val core = formatter.format(amount.setScale(2, RoundingMode.HALF_UP))
        return if (includeSymbol) "$core USDT" else core
    }

    fun shortAddress(address: String): String {
        val trimmed = address.trim()
        if (trimmed.length <= 12) return trimmed
        return "${trimmed.take(6)}…${trimmed.takeLast(4)}"
    }

    fun isPlausibleTronTransactionId(txId: String): Boolean {
        val trimmed = txId.trim()
        return trimmed.length == 64 && trimmed.all { it.isDigit() || it in 'a'..'f' || it in 'A'..'F' }
    }
}

object SendAmountParser {
    fun parse(text: String): BigDecimal? {
        val normalized = text.trim().replace(",", ".")
        if (normalized.isEmpty()) return null
        return normalized.toBigDecimalOrNull()?.takeIf { it > BigDecimal.ZERO }
    }
}
