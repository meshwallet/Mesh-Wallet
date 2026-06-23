package com.mesh.wallet.data.tron

import com.mesh.wallet.core.config.TronConfiguration
import com.mesh.wallet.core.network.MeshNetworkSponsorship
import com.mesh.wallet.data.relay.MeshEnergyBrokerService
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import wallet.core.java.AnySigner
import wallet.core.jni.CoinType
import wallet.core.jni.proto.Common
import wallet.core.jni.proto.Tron
import java.math.BigDecimal

data class TronUsdtTransferResult(
    val txId: String,
    val rawJson: String
)

object TronTransactionService {
    private val json = Json { ignoreUnknownKeys = true }

    suspend fun sendUsdt(
        signingKey: ByteArray,
        fromAddress: String,
        toAddress: String,
        amount: BigDecimal,
        feeLimit: Long = TronConfiguration.DEFAULT_FEE_LIMIT,
        skipNetworkPrepare: Boolean = false
    ): TronUsdtTransferResult {
        require(TronWalletService.isValidTronAddress(toAddress)) { throw TronApiException.InvalidAddress }
        require(TronWalletService.isValidTronAddress(fromAddress)) { throw TronApiException.InvalidAddress }

        if (MeshNetworkSponsorship.isEnabled && !skipNetworkPrepare) {
            MeshEnergyBrokerService.prepareSender(fromAddress, toAddress)
        }

        val smallestUnits = TronAmountEncoder.usdtToSmallestUnits(amount)
        val block = TronBlockService.fetchLatestBlock()
        val signed = signUsdtTransaction(
            signingKey = signingKey,
            fromAddress = fromAddress,
            toAddress = toAddress,
            smallestUnits = smallestUnits,
            block = block,
            feeLimit = feeLimit,
            expirationOffsetMs = 3_600_000L
        )

        val broadcast = broadcastSignedTransaction(signed.rawJson)
        return TronUsdtTransferResult(txId = broadcast, rawJson = signed.rawJson)
    }

    suspend fun buildSignedUsdtTransaction(
        signingKey: ByteArray,
        fromAddress: String,
        toAddress: String,
        amount: BigDecimal,
        feeLimit: Long = TronConfiguration.DEFAULT_FEE_LIMIT,
        expirationOffsetMs: Long = 86_400_000L
    ): TronUsdtTransferResult {
        val smallestUnits = TronAmountEncoder.usdtToSmallestUnits(amount)
        val block = TronBlockService.fetchLatestBlock()
        val signed = signUsdtTransaction(
            signingKey = signingKey,
            fromAddress = fromAddress,
            toAddress = toAddress,
            smallestUnits = smallestUnits,
            block = block,
            feeLimit = feeLimit,
            expirationOffsetMs = expirationOffsetMs
        )
        return TronUsdtTransferResult(txId = signed.txId, rawJson = signed.rawJson)
    }

    suspend fun broadcastSignedTransaction(rawJson: String): String {
        val body = Json.parseToJsonElement(rawJson).jsonObject
        val raw = TronApiClient.post("/wallet/broadcasttransaction", body)
        val decoded = json.decodeFromString<TronBroadcastResponse>(raw)
        val txId = decoded.txid
        if (decoded.result == true && !txId.isNullOrBlank()) return txId
        throw TronApiException.BroadcastFailed(decoded.message ?: decoded.code ?: "unknown")
    }

    private fun signUsdtTransaction(
        signingKey: ByteArray,
        fromAddress: String,
        toAddress: String,
        smallestUnits: Long,
        block: TronChainBlock,
        feeLimit: Long,
        expirationOffsetMs: Long
    ): TronUsdtTransferResult {
        val input = Tron.SigningInput.newBuilder()
            .setPrivateKey(com.google.protobuf.ByteString.copyFrom(signingKey))
            .setTransaction(
                Tron.Transaction.newBuilder()
                    .setTimestamp(block.timestamp)
                    .setExpiration(block.timestamp + expirationOffsetMs)
                    .setFeeLimit(feeLimit)
                    .setBlockHeader(block.header)
                    .setTransferTrc20Contract(
                        Tron.TransferTRC20Contract.newBuilder()
                            .setOwnerAddress(fromAddress)
                            .setContractAddress(TronConfiguration.usdtContractAddress)
                            .setToAddress(toAddress)
                            .setAmount(
                                com.google.protobuf.ByteString.copyFrom(
                                    TronAmountEncoder.encodeUInt256(smallestUnits)
                                )
                            )
                            .build()
                    )
                    .build()
            )
            .build()

        val output = AnySigner.sign(input, CoinType.TRON, Tron.SigningOutput.parser())
        if (output.error != Common.SigningError.OK || output.json.isNullOrBlank()) {
            throw TronApiException.BroadcastFailed("Signing failed")
        }
        val broadcastBody = Json.parseToJsonElement(output.json).jsonObject
        val txId = broadcastBody["txID"]?.jsonPrimitive?.content
            ?: broadcastBody["txid"]?.jsonPrimitive?.content
            ?: ""
        return TronUsdtTransferResult(txId = txId, rawJson = output.json)
    }
}

@Serializable
private data class TronBroadcastResponse(
    val result: Boolean? = null,
    val txid: String? = null,
    val code: String? = null,
    val message: String? = null
)
