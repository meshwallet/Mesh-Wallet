package com.mesh.wallet.core.config

import com.mesh.wallet.BuildConfig
import java.math.BigDecimal

object TronConfiguration {
    const val NETWORK_NAME = "Tron Mainnet"
    const val COIN_SYMBOL = "TRX"
    const val TOKEN_SYMBOL = "USDT"
    const val TOKEN_DECIMALS = 6
    const val DEFAULT_FEE_LIMIT = 30_000_000L
    const val DEFAULT_DERIVATION_PATH = "m/44'/195'/0'/0/0"

    val usdtContractAddress: String = BuildConfig.USDT_CONTRACT
    val tronGridBaseUrl: String = BuildConfig.TRONGRID_BASE_URL
    val relayBaseUrl: String = BuildConfig.RELAY_URL
    val relayAuthSecret: String = BuildConfig.RELAY_AUTH
    val feeTreasuryAddress: String = BuildConfig.FEE_TREASURY
    val sendRouterAddress: String = BuildConfig.SEND_ROUTER

    val trongridApiKeys: List<String> = BuildConfig.TRONGRID_API_KEYS
        .split(",")
        .map { it.trim() }
        .filter { it.isNotEmpty() }

    fun receiveDerivationPath(accountIndex: Int): String = "m/44'/195'/0'/0/$accountIndex"

    fun relayDerivationPath(accountIndex: Int): String = "m/44'/195'/0'/1/$accountIndex"

    fun formatUsdt(amount: BigDecimal, includeSymbol: Boolean = true): String {
        val formatted = amount.setScale(2, java.math.RoundingMode.HALF_UP).toPlainString()
        return if (includeSymbol) "$$formatted" else formatted
    }
}
