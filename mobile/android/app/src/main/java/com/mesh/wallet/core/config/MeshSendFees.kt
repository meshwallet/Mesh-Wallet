package com.mesh.wallet.core.config

import java.math.BigDecimal

object MeshSendFees {
    val directSend: BigDecimal = BigDecimal("2")
    const val chargesOnChainFee = false
    const val showsFeeInUI = true

    fun networkFee(): BigDecimal = directSend

    fun formattedFee(fee: BigDecimal): String = TronConfiguration.formatUsdt(fee)

    val usesSendRouter: Boolean
        get() = chargesOnChainFee && TronConfiguration.sendRouterAddress.isNotBlank() &&
            TronConfiguration.feeTreasuryAddress.isNotBlank()
}

