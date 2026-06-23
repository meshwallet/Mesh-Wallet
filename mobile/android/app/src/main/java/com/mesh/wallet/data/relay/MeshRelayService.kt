package com.mesh.wallet.data.relay

import com.mesh.wallet.core.network.MeshHTTPClient
import com.mesh.wallet.core.network.MeshNetworkSponsorship
import com.mesh.wallet.core.network.SendErrorPresenter
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

object MeshRelayService {
    private val json = Json { ignoreUnknownKeys = true }

    suspend fun healthCheck(): Boolean = runCatching {
        get("/v1/health").let { true }
    }.getOrDefault(false)

    suspend fun activateAddress(address: String) {
        post("/v1/activate", buildJsonObject { put("address", address) })
    }

    suspend fun prepareSender(
        address: String,
        toAddress: String,
        highEnergy: Boolean = false,
        skipRecipientActivation: Boolean = false
    ): PrepareSenderResponse {
        val body = buildJsonObject {
            put("address", address)
            put("toAddress", toAddress)
            put("highEnergy", highEnergy)
            put("skipRecipientActivation", skipRecipientActivation)
        }
        val raw = post("/v1/prepare-sender", body)
        return json.decodeFromString(raw)
    }

    suspend fun registerSendFee(payload: RegisterSendFeePayload): RegisterSendFeeResponse {
        val raw = post("/v1/register-send-fee", json.encodeToString(payload))
        return json.decodeFromString(raw)
    }

    suspend fun fetchSendStatus(id: String): SendStatusResponse {
        return json.decodeFromString(get("/v1/send-status?id=$id"))
    }

    suspend fun fetchWalletFeeStatus(address: String): WalletFeeStatusResponse {
        return json.decodeFromString(get("/v1/wallet-fee-status?address=$address"))
    }

    suspend fun continueQueuedSend(id: String) {
        post("/v1/continue-queued-send", buildJsonObject { put("id", id) })
    }

    suspend fun settleSendFee(payload: JsonObject) {
        post("/v1/settle-send-fee", payload)
    }

    suspend fun settleQueuedSendFee(payload: JsonObject) {
        post("/v1/settle-queued-send-fee", payload)
    }

    suspend fun clearWalletDelinquent(address: String) {
        post("/v1/clear-wallet-delinquent", buildJsonObject { put("address", address) })
    }

    suspend fun opsStatus(): OpsStatusResponse =
        json.decodeFromString(get("/v1/ops-status"))

    suspend fun payNetworkFee(userAddress: String, feeUsdt: String, treasury: String) {
        post(
            "/v1/pay-network-fee",
            buildJsonObject {
                put("userAddress", userAddress)
                put("feeUSDT", feeUsdt)
                put("treasury", treasury)
            }
        )
    }

    private suspend fun get(path: String): String {
        val base = MeshNetworkSponsorship.relayBaseUrl
            ?: throw IllegalStateException("Relay not configured")
        val request = Request.Builder()
            .url("$base$path")
            .get()
            .applyAuth()
            .build()
        val (body, code) = MeshHTTPClient.relayExecute(request)
        if (code !in 200..299) {
            throw IllegalStateException(SendErrorPresenter.relayFailureMessage(body.decodeToString(), code))
        }
        return body.decodeToString()
    }

    private suspend fun post(path: String, body: JsonObject): String =
        post(path, json.encodeToString(body))

    private suspend fun post(path: String, body: String): String {
        val base = MeshNetworkSponsorship.relayBaseUrl
            ?: throw IllegalStateException("Relay not configured")
        val requestBody = body.toRequestBody("application/json".toMediaType())
        val request = Request.Builder()
            .url("$base$path")
            .post(requestBody)
            .applyAuth()
            .build()
        val (bytes, code) = MeshHTTPClient.relayExecute(request)
        if (code !in 200..299) {
            throw IllegalStateException(SendErrorPresenter.relayFailureMessage(bytes.decodeToString(), code))
        }
        return bytes.decodeToString()
    }

    private fun Request.Builder.applyAuth(): Request.Builder {
        MeshNetworkSponsorship.relayAuthSecret?.let { secret ->
            addHeader("Authorization", "Bearer $secret")
        }
        return this
    }
}

@Serializable
data class PrepareSenderResponse(
    val ok: Boolean = false,
    val message: String? = null,
    val energy: Int? = null
)

@Serializable
data class RegisterSendFeePayload(
    val id: String,
    val userAddress: String,
    val recipientAddress: String,
    val amountUSDT: String,
    val feeUSDT: String,
    val signedMainTxJSON: String? = null,
    val signedFeeTxJSON: String? = null,
    val steps: List<QueuedSendStep>? = null
)

@Serializable
data class QueuedSendStep(
    val signedTxJSON: String,
    val fromAddress: String,
    val toAddress: String
)

@Serializable
data class RegisterSendFeeResponse(
    val ok: Boolean = false,
    val id: String? = null,
    val message: String? = null
)

@Serializable
data class SendStatusResponse(
    val ok: Boolean = false,
    val status: String? = null,
    val txId: String? = null,
    val message: String? = null
)

@Serializable
data class WalletFeeStatusResponse(
    val delinquent: Boolean = false
)

@Serializable
data class OpsStatusResponse(
    val ok: Boolean = false,
    val usdtBalance: String? = null
)
