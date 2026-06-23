package com.mesh.wallet.data.tron

import com.mesh.wallet.core.config.TronConfiguration
import java.math.BigDecimal
import java.math.RoundingMode

object TronAmountEncoder {
    fun usdtToSmallestUnits(amount: BigDecimal): Long {
        require(amount > BigDecimal.ZERO) { "Invalid amount" }
        val scaled = amount.multiply(BigDecimal.TEN.pow(TronConfiguration.TOKEN_DECIMALS))
            .setScale(0, RoundingMode.HALF_UP)
        val value = scaled.longValueExact()
        require(value > 0) { "Invalid amount" }
        return value
    }

    fun smallestUnitsToUsdt(smallestUnits: Long): BigDecimal =
        BigDecimal(smallestUnits).divide(BigDecimal.TEN.pow(TronConfiguration.TOKEN_DECIMALS))

    fun encodeUInt256(smallestUnits: Long): ByteArray {
        val data = ByteArray(32)
        var value = smallestUnits
        var index = 31
        while (value > 0 && index >= 0) {
            data[index] = (value and 0xff).toByte()
            value = value ushr 8
            index--
        }
        return data
    }
}
