package com.mesh.wallet.data.tron

import com.mesh.wallet.core.config.TronConfiguration
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import com.mesh.wallet.BuildConfig
import okhttp3.logging.HttpLoggingInterceptor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

object TronApiClient {
    private val json = Json { ignoreUnknownKeys = true }
    private val keyIndex = AtomicInteger(0)

    private val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .apply {
            if (BuildConfig.DEBUG) {
                addInterceptor(HttpLoggingInterceptor().apply {
                    level = HttpLoggingInterceptor.Level.BASIC
                })
            }
        }
        .build()

    suspend fun post(path: String, body: JsonObject): String = withContext(Dispatchers.IO) {
        val requestBody = body.toString().toRequestBody("application/json".toMediaType())
        val request = Request.Builder()
            .url("${TronConfiguration.tronGridBaseUrl}$path")
            .post(requestBody)
            .apply { addTronGridKey(this) }
            .build()
        client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) error("TronGrid error: ${response.code}")
            response.body?.string().orEmpty()
        }
    }

    suspend fun get(path: String, query: Map<String, String> = emptyMap()): String = withContext(Dispatchers.IO) {
        val urlBuilder = StringBuilder("${TronConfiguration.tronGridBaseUrl}$path")
        if (query.isNotEmpty()) {
            urlBuilder.append("?")
            urlBuilder.append(query.entries.joinToString("&") { "${it.key}=${it.value}" })
        }
        val request = Request.Builder()
            .url(urlBuilder.toString())
            .get()
            .apply { addTronGridKey(this) }
            .build()
        client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) error("TronGrid error: ${response.code}")
            response.body?.string().orEmpty()
        }
    }

    fun accountBody(address: String): JsonObject = buildJsonObject {
        put("address", address)
        put("visible", true)
    }

    private fun addTronGridKey(builder: Request.Builder) {
        val keys = TronConfiguration.trongridApiKeys
        if (keys.isNotEmpty()) {
            val key = keys[keyIndex.getAndIncrement() % keys.size]
            builder.addHeader("TRON-PRO-API-KEY", key)
        }
    }

}
