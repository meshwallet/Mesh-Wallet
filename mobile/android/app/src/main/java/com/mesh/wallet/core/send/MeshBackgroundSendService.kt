package com.mesh.wallet.core.send

import com.mesh.wallet.core.config.MeshSendFees
import com.mesh.wallet.core.network.SendErrorPresenter
import com.mesh.wallet.data.MeshSendRouterService
import com.mesh.wallet.data.MeshWalletCredentials
import com.mesh.wallet.data.privacy.MeshPrivacyService
import com.mesh.wallet.data.relay.MeshRelayService
import com.mesh.wallet.data.relay.RegisterSendFeePayload
import com.mesh.wallet.data.tron.TronTransactionService
import com.mesh.wallet.domain.model.TransactionStatus
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.math.BigDecimal
import java.util.UUID

data class PendingTransfer(
    val id: String,
    val walletId: String,
    val recipientAddress: String,
    val amountUsdt: BigDecimal,
    val amountText: String,
    val fromAddress: String,
    val selectedSendSlotIndex: Int,
    val status: TransactionStatus = TransactionStatus.PROCESSING,
    val txId: String? = null,
    val errorMessage: String? = null
)

class MeshBackgroundSendService(
    private val credentials: MeshWalletCredentials,
    private val privacyService: MeshPrivacyService,
    private val pendingSendStore: MeshPendingSendStore
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val _current = MutableStateFlow<PendingTransfer?>(null)
    val current: StateFlow<PendingTransfer?> = _current.asStateFlow()

    private val _isFeeDelinquent = MutableStateFlow(false)
    val isFeeDelinquent: StateFlow<Boolean> = _isFeeDelinquent.asStateFlow()

    private val balanceHolds = mutableMapOf<String, BigDecimal>()

    fun spendableUsdt(walletId: String, chainBalance: BigDecimal): BigDecimal {
        val hold = balanceHolds[walletId] ?: BigDecimal.ZERO
        return (chainBalance - hold).coerceAtLeast(BigDecimal.ZERO)
    }

    fun beginSend(
        walletId: String,
        recipientAddress: String,
        amount: BigDecimal,
        amountText: String,
        slotIndex: Int,
        onProgress: ((String) -> Unit)? = null,
        onComplete: (Result<String>) -> Unit
    ) {
        val transferId = UUID.randomUUID().toString()
        scope.launch {
            runCatching {
                val spend = privacyService.resolveSpendSource(walletId, slotIndex)
                val fee = MeshSendFees.networkFee()
                val holdAmount = amount + fee
                balanceHolds[walletId] = (balanceHolds[walletId] ?: BigDecimal.ZERO) + holdAmount

                val pending = PendingTransfer(
                    id = transferId,
                    walletId = walletId,
                    recipientAddress = recipientAddress,
                    amountUsdt = amount,
                    amountText = amountText,
                    fromAddress = spend.address,
                    selectedSendSlotIndex = slotIndex
                )
                _current.value = pending

                pendingSendStore.save(
                    PendingSendRecord(
                        id = transferId,
                        walletId = walletId,
                        recipientAddress = recipientAddress,
                        amountText = amountText,
                        amountUsdt = amount.toPlainString(),
                        selectedSendSlotIndex = slotIndex,
                        fromAddress = spend.address
                    )
                )

                val txId = when {
                    MeshSendRouterService.isConfigured -> {
                        onProgress?.invoke("Preparing direct send…")
                        val result = MeshSendRouterService.performOnDeviceDirectSend(
                            spendSource = spend,
                            recipient = recipientAddress,
                            recipientAmount = amount,
                            feeAmount = fee,
                            credentials = credentials,
                            statusUpdate = onProgress
                        )
                        result.txId
                    }
                    else -> {
                        onProgress?.invoke("Sending USDT…")
                        val signingKey = credentials.signingKey(walletId, spend.derivationPath)
                        TronTransactionService.sendUsdt(
                            signingKey = signingKey,
                            fromAddress = spend.address,
                            toAddress = recipientAddress,
                            amount = amount
                        ).txId
                    }
                }

                val obligationId = registerWithWorkerIfNeeded(
                    transferId, walletId, recipientAddress, amount, txId
                )
                pollUntilSettled(transferId, obligationId)

                _current.value = pending.copy(status = TransactionStatus.CONFIRMED, txId = txId)
                pendingSendStore.remove(transferId)
                balanceHolds[walletId] = (balanceHolds[walletId] ?: BigDecimal.ZERO) - holdAmount
                onComplete(Result.success(txId))
            }.onFailure { error ->
                _current.value = _current.value?.copy(
                    status = TransactionStatus.FAILED,
                    errorMessage = SendErrorPresenter.messageFor(error)
                )
                onComplete(Result.failure(error))
            }
        }
    }

    fun resumeProcessingSendsIfNeeded(walletId: String) {
        scope.launch {
            pendingSendStore.loadForWallet(walletId).forEach { refreshWorkerStatus(it.id) }
            refreshFeeStatus(walletId)
        }
    }

    suspend fun refreshFeeStatus(walletId: String) {
        val wallet = credentials.resolve(walletId)
        val status = runCatching { MeshRelayService.fetchWalletFeeStatus(wallet.address) }.getOrNull()
        _isFeeDelinquent.value = status?.delinquent == true
    }

    private suspend fun registerWithWorkerIfNeeded(
        transferId: String,
        walletId: String,
        recipient: String,
        amount: BigDecimal,
        signedMainTxJson: String
    ): String? {
        if (!MeshSendFees.chargesOnChainFee) return null
        val wallet = credentials.resolve(walletId)
        val fee = MeshSendFees.networkFee()
        val response = MeshRelayService.registerSendFee(
            RegisterSendFeePayload(
                id = transferId,
                userAddress = wallet.address,
                recipientAddress = recipient,
                amountUSDT = amount.toPlainString(),
                feeUSDT = fee.toPlainString(),
                signedMainTxJSON = signedMainTxJson
            )
        )
        return response.id
    }

    private suspend fun pollUntilSettled(transferId: String, obligationId: String?) {
        repeat(60) {
            val status = runCatching { MeshRelayService.fetchSendStatus(obligationId ?: transferId) }.getOrNull()
            when (status?.status?.lowercase()) {
                "confirmed", "settled", "complete", "success" -> return
                "failed", "error" -> throw IllegalStateException(status.message ?: "Send failed")
            }
            delay(2_000)
        }
    }

    private suspend fun refreshWorkerStatus(id: String) {
        runCatching { MeshRelayService.fetchSendStatus(id) }
    }
}
