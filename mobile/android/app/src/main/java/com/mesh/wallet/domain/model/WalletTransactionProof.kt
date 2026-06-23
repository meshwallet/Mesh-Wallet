package com.mesh.wallet.domain.model

import com.mesh.wallet.data.tron.TronUSDTService
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

fun WalletTransaction.formattedDateTime(): String =
    SimpleDateFormat("MMM d, yyyy HH:mm", Locale.getDefault()).format(Date(timestamp))

fun WalletTransaction.proofAmountText(): String =
    "${TronUSDTService.formatUsdtAmount(amount, includeSymbol = false)} USDT"

fun WalletTransaction.proofShortCounterparty(): String =
    TronUSDTService.shortAddress(counterpartyAddress)

fun WalletTransaction.proofShortTxId(): String =
    txId?.let { TronUSDTService.shortAddress(it) } ?: "—"

fun WalletTransaction.proofShareText(): String = buildString {
    appendLine(if (direction == TransactionDirection.INCOMING) "Received" else "Sent")
    appendLine()
    appendLine(proofAmountText())
    appendLine()
    appendLine("Status: Confirmed")
    appendLine("Network: Tron")
    appendLine("${if (direction == TransactionDirection.OUTGOING) "To" else "From"}: ${proofShortCounterparty()}")
    appendLine("Tx: ${proofShortTxId()}")
    appendLine(formattedDateTime())
    appendLine()
    appendLine("Sent with Mesh Wallet")
}
