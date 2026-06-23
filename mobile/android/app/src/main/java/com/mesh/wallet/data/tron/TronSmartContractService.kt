package com.mesh.wallet.data.tron

import com.mesh.wallet.core.config.TronConfiguration
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import wallet.core.java.AnySigner
import wallet.core.jni.CoinType
import wallet.core.jni.proto.Common
import wallet.core.jni.proto.Tron
import java.math.BigDecimal

object TronSmartContractService {
    private const val ROUTER_FEE_LIMIT = 150_000_000L
    private const val APPROVE_FEE_LIMIT = 80_000_000L
    private const val EXPIRATION_OFFSET_MS = 3_600_000L

    suspend fun usdtAllowance(owner: String, spender: String): Long {
        val parameter = MeshABIEncoder.encodeAllowanceParameter(owner, spender)
        val body = buildJsonObject {
            put("owner_address", owner)
            put("contract_address", TronConfiguration.usdtContractAddress)
            put("function_selector", "allowance(address,address)")
            put("parameter", parameter)
            put("visible", true)
        }
        val raw = TronApiClient.post("/wallet/triggerconstantcontract", body)
        val hex = """"constant_result"\s*:\s*\[\s*"([0-9a-fA-F]+)"""".toRegex().find(raw)?.groupValues?.getOrNull(1)
            ?: return 0L
        val bytes = hex.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
        if (bytes.size < 32) return 0L
        return bytes.takeLast(32).fold(0L) { acc, b -> (acc shl 8) or (b.toLong() and 0xff) }
    }

    suspend fun buildSignedApprove(
        signingKey: ByteArray,
        fromAddress: String,
        spender: String,
        chainBlock: TronChainBlock? = null
    ): TronUsdtTransferResult {
        val callData = MeshABIEncoder.encodeApproveCallData(spender)
        return signTriggerSmartContract(signingKey, fromAddress, TronConfiguration.usdtContractAddress, callData, APPROVE_FEE_LIMIT, chainBlock)
    }

    suspend fun buildSignedSendWithFee(
        signingKey: ByteArray,
        fromAddress: String,
        routerAddress: String,
        recipient: String,
        recipientAmount: BigDecimal,
        feeAmount: BigDecimal,
        chainBlock: TronChainBlock? = null
    ): TronUsdtTransferResult {
        val recipientUnits = TronAmountEncoder.usdtToSmallestUnits(recipientAmount)
        val feeUnits = TronAmountEncoder.usdtToSmallestUnits(feeAmount)
        val callData = MeshABIEncoder.encodeSendWithFeeCallData(recipient, recipientUnits, feeUnits)
        return signTriggerSmartContract(signingKey, fromAddress, routerAddress, callData, ROUTER_FEE_LIMIT, chainBlock)
    }

    private suspend fun signTriggerSmartContract(
        signingKey: ByteArray,
        ownerAddress: String,
        contractAddress: String,
        callData: ByteArray,
        feeLimit: Long,
        chainBlock: TronChainBlock?
    ): TronUsdtTransferResult {
        val block = chainBlock ?: TronBlockService.fetchLatestBlock()
        val input = Tron.SigningInput.newBuilder()
            .setPrivateKey(com.google.protobuf.ByteString.copyFrom(signingKey))
            .setTransaction(
                Tron.Transaction.newBuilder()
                    .setTimestamp(block.timestamp)
                    .setExpiration(block.timestamp + EXPIRATION_OFFSET_MS)
                    .setFeeLimit(feeLimit)
                    .setBlockHeader(block.header)
                    .setTriggerSmartContract(
                        Tron.TriggerSmartContract.newBuilder()
                            .setOwnerAddress(ownerAddress)
                            .setContractAddress(contractAddress)
                            .setCallValue(0)
                            .setData(com.google.protobuf.ByteString.copyFrom(callData))
                            .build()
                    )
                    .build()
            )
            .build()

        val output = AnySigner.sign(input, CoinType.TRON, Tron.SigningOutput.parser())
        if (output.error != Common.SigningError.OK || output.json.isNullOrBlank()) {
            throw TronApiException.BroadcastFailed("Contract signing failed")
        }
        val txId = """"txID"\s*:\s*"([^"]+)"""".toRegex().find(output.json)?.groupValues?.getOrNull(1).orEmpty()
        return TronUsdtTransferResult(txId = txId, rawJson = output.json)
    }
}
