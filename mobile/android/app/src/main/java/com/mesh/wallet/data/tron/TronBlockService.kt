package com.mesh.wallet.data.tron

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import wallet.core.jni.proto.Tron.BlockHeader

data class TronChainBlock(
    val timestamp: Long,
    val header: BlockHeader
)

object TronBlockService {
    private val json = Json { ignoreUnknownKeys = true }
    @Volatile private var cachedBlock: TronChainBlock? = null
    @Volatile private var cachedAt: Long = 0L
    private const val CACHE_LIFETIME_MS = 3_000L

    suspend fun fetchLatestBlock(): TronChainBlock {
        val now = System.currentTimeMillis()
        val cached = cachedBlock
        if (cached != null && now - cachedAt < CACHE_LIFETIME_MS) return cached
        val block = fetchLatestBlockFromNetwork()
        cachedBlock = block
        cachedAt = now
        return block
    }

    fun prefetchLatestBlock() {
        // Fire-and-forget warmup from UI review screen
    }

    private suspend fun fetchLatestBlockFromNetwork(): TronChainBlock {
        val raw = TronApiClient.post("/wallet/getnowblock", kotlinx.serialization.json.buildJsonObject {})
        val decoded = json.decodeFromString<TronNowBlockResponse>(raw)
        val rawData = decoded.blockHeader?.rawData
            ?: throw TronApiException.DecodingFailed
        val timestamp = rawData.timestamp ?: throw TronApiException.DecodingFailed
        val number = rawData.number ?: throw TronApiException.DecodingFailed
        val version = rawData.version ?: throw TronApiException.DecodingFailed
        val txTrieRoot = hexToBytes(normalizeHex(rawData.txTrieRoot ?: throw TronApiException.DecodingFailed))
        val parentHash = hexToBytes(normalizeHex(rawData.parentHash ?: throw TronApiException.DecodingFailed))
        val witness = hexToBytes(normalizeHex(rawData.witnessAddress ?: throw TronApiException.DecodingFailed))

        val header = BlockHeader.newBuilder()
            .setTimestamp(timestamp)
            .setNumber(number)
            .setVersion(version)
            .setTxTrieRoot(com.google.protobuf.ByteString.copyFrom(txTrieRoot))
            .setParentHash(com.google.protobuf.ByteString.copyFrom(parentHash))
            .setWitnessAddress(com.google.protobuf.ByteString.copyFrom(witness))
            .build()

        return TronChainBlock(timestamp = timestamp, header = header)
    }

    private fun normalizeHex(value: String): String {
        val trimmed = value.trim()
        return if (trimmed.startsWith("0x", ignoreCase = true)) trimmed.drop(2) else trimmed
    }

    private fun hexToBytes(hex: String): ByteArray =
        hex.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
}

@Serializable
private data class TronNowBlockResponse(
    @SerialName("block_header") val blockHeader: TronBlockHeaderWrapper? = null
)

@Serializable
private data class TronBlockHeaderWrapper(
    @SerialName("raw_data") val rawData: TronBlockRawData? = null
)

@Serializable
private data class TronBlockRawData(
    val number: Long? = null,
    val timestamp: Long? = null,
    @SerialName("txTrieRoot") val txTrieRoot: String? = null,
    @SerialName("parentHash") val parentHash: String? = null,
    @SerialName("witness_address") val witnessAddress: String? = null,
    val version: Int? = null
)

sealed class TronApiException(message: String) : Exception(message) {
    data object DecodingFailed : TronApiException("Failed to decode Tron response")
    data object InvalidAddress : TronApiException("Invalid Tron address")
    data object InvalidAmount : TronApiException("Invalid amount")
    data class BroadcastFailed(val reason: String) : TronApiException(reason)
}
