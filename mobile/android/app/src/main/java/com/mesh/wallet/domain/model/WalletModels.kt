package com.mesh.wallet.domain.model

import kotlinx.serialization.Serializable
import java.math.BigDecimal
import java.util.UUID

@Serializable
enum class WalletImportKind {
    MNEMONIC,
    PRIVATE_KEY
}

enum class WalletPhraseFlow {
    CREATED,
    RESTORED
}

@Serializable
data class StoredWallet(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val address: String,
    val createdAt: Long = System.currentTimeMillis(),
    val importKind: WalletImportKind = WalletImportKind.MNEMONIC
)

enum class TransactionDirection {
    INCOMING,
    OUTGOING
}

enum class TransactionStatus {
    PROCESSING,
    CONFIRMED,
    FAILED
}

data class WalletTransaction(
    val id: String,
    val txId: String?,
    val direction: TransactionDirection,
    val amount: BigDecimal,
    val counterpartyAddress: String,
    val timestamp: Long,
    val status: TransactionStatus = TransactionStatus.CONFIRMED,
    val isPrivate: Boolean = false
)

data class TronAccountBalance(
    val trxBalance: Double = 0.0,
    val usdtBalance: BigDecimal = BigDecimal.ZERO,
    val transactionCount: Int = 0
)

data class WalletReceiveSlot(
    val index: Int,
    val address: String,
    val name: String,
    val balanceUsdt: BigDecimal? = null
)

data class PendingWalletDraft(
    val words: List<String>? = null,
    val address: String? = null,
    val privateKeyHex: String? = null,
    val walletName: String? = null,
    val importKind: WalletImportKind = WalletImportKind.MNEMONIC,
    val flow: WalletPhraseFlow = WalletPhraseFlow.CREATED
)
