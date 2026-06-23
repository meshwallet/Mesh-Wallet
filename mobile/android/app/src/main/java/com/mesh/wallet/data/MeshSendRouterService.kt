package com.mesh.wallet.data

import com.mesh.wallet.core.config.MeshSendFees
import com.mesh.wallet.core.config.TronConfiguration
import com.mesh.wallet.core.network.MeshNetworkSponsorship
import com.mesh.wallet.data.privacy.MeshPrivacyService
import com.mesh.wallet.data.relay.MeshEnergyBrokerService
import com.mesh.wallet.data.tron.TronAmountEncoder
import com.mesh.wallet.data.tron.TronApiException
import com.mesh.wallet.data.tron.TronBlockService
import com.mesh.wallet.data.tron.TronSmartContractService
import com.mesh.wallet.data.tron.TronTransactionService
import com.mesh.wallet.data.tron.TronUsdtTransferResult
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import java.math.BigDecimal

object MeshSendRouterService {
    val isConfigured: Boolean get() = MeshSendFees.usesSendRouter

    suspend fun performOnDeviceDirectSend(
        spendSource: MeshPrivacyService.SpendSource,
        recipient: String,
        recipientAmount: BigDecimal,
        feeAmount: BigDecimal,
        credentials: MeshWalletCredentials,
        statusUpdate: ((String) -> Unit)? = null
    ): TronUsdtTransferResult {
        val signed = buildSignedDirectSend(spendSource, recipient, recipientAmount, feeAmount, credentials, statusUpdate)
        statusUpdate?.invoke("Sending USDT…")
        val txId = TronTransactionService.broadcastSignedTransaction(signed.rawJson)
        return TronUsdtTransferResult(txId = txId, rawJson = signed.rawJson)
    }

    suspend fun buildSignedDirectSend(
        spendSource: MeshPrivacyService.SpendSource,
        recipient: String,
        recipientAmount: BigDecimal,
        feeAmount: BigDecimal,
        credentials: MeshWalletCredentials,
        statusUpdate: ((String) -> Unit)? = null
    ): TronUsdtTransferResult {
        val router = TronConfiguration.sendRouterAddress
        require(router.isNotBlank()) { throw TronApiException.BroadcastFailed("Send router is not configured.") }

        val recipientUnits = TronAmountEncoder.usdtToSmallestUnits(recipientAmount)
        val feeUnits = TronAmountEncoder.usdtToSmallestUnits(feeAmount)
        val required = recipientUnits + feeUnits

        ensureUsdtAllowance(spendSource, required, credentials, statusUpdate)

        if (MeshNetworkSponsorship.isEnabled) {
            statusUpdate?.invoke("Preparing network…")
            MeshEnergyBrokerService.prepareSender(
                address = spendSource.address,
                toAddress = router,
                highEnergy = true,
                skipRecipientActivation = true
            )
            MeshEnergyBrokerService.requireSenderReady(spendSource.address, MeshEnergyBrokerService.preferredTransferEnergy())
        }

        val signingKey = credentials.signingKey(derivationPath = spendSource.derivationPath)
        return TronSmartContractService.buildSignedSendWithFee(
            signingKey = signingKey,
            fromAddress = spendSource.address,
            routerAddress = router,
            recipient = recipient,
            recipientAmount = recipientAmount,
            feeAmount = feeAmount
        )
    }

    private suspend fun ensureUsdtAllowance(
        spendSource: MeshPrivacyService.SpendSource,
        requiredTotal: Long,
        credentials: MeshWalletCredentials,
        statusUpdate: ((String) -> Unit)?
    ) {
        val router = TronConfiguration.sendRouterAddress
        if (TronSmartContractService.usdtAllowance(spendSource.address, router) >= requiredTotal) return

        statusUpdate?.invoke("Authorizing USDT…")
        if (MeshNetworkSponsorship.isEnabled) {
            MeshEnergyBrokerService.prepareSender(
                address = spendSource.address,
                toAddress = TronConfiguration.usdtContractAddress,
                highEnergy = false,
                skipRecipientActivation = true
            )
            MeshEnergyBrokerService.requireSenderReady(spendSource.address, MeshEnergyBrokerService.energyMinimum(false))
        }

        val signingKey = credentials.signingKey(derivationPath = spendSource.derivationPath)
        val signed = TronSmartContractService.buildSignedApprove(signingKey, spendSource.address, router)
        TronTransactionService.broadcastSignedTransaction(signed.rawJson)

        repeat(30) {
            if (TronSmartContractService.usdtAllowance(spendSource.address, router) >= requiredTotal) return
            kotlinx.coroutines.delay(1_000)
        }
        throw TronApiException.BroadcastFailed("USDT allowance not ready.")
    }
}
