package com.mesh.wallet.core.network

import kotlinx.coroutines.delay
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.IOException
import java.net.SocketTimeoutException
import java.util.concurrent.TimeUnit

object MeshHTTPClient {
    private val relayClient: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(120, TimeUnit.SECONDS)
        .readTimeout(180, TimeUnit.SECONDS)
        .writeTimeout(120, TimeUnit.SECONDS)
        .build()

    private val apiClient: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .build()

    suspend fun relayExecute(request: Request): Pair<ByteArray, Int> {
        val backoffMs = listOf(0L, 900L, 2_200L, 5_000L)
        var lastRateLimited: Pair<ByteArray, Int>? = null

        for (delayMs in backoffMs) {
            if (delayMs > 0) delay(delayMs)
            val result = runCatching { executeOnce(request, relayClient, retries = 2) }
            val (body, code) = result.getOrElse { throw it }
            if (code == 429) {
                lastRateLimited = body to code
                continue
            }
            return body to code
        }
        return lastRateLimited ?: executeOnce(request, relayClient, retries = 2)
    }

    suspend fun apiExecute(request: Request): Pair<ByteArray, Int> =
        executeOnce(request, apiClient, retries = 1)

    private suspend fun executeOnce(
        request: Request,
        client: OkHttpClient,
        retries: Int
    ): Pair<ByteArray, Int> {
        var lastError: Exception? = null
        repeat(retries + 1) { attempt ->
            try {
                client.newCall(request).execute().use { response ->
                    return (response.body?.bytes() ?: ByteArray(0)) to response.code
                }
            } catch (e: Exception) {
                lastError = e as? Exception ?: IOException(e)
                if (attempt < retries && shouldRetry(e)) {
                    delay(1_000)
                } else {
                    throw e
                }
            }
        }
        throw lastError ?: IOException("Unknown network error")
    }

    private fun shouldRetry(error: Throwable): Boolean =
        error is SocketTimeoutException ||
            error is IOException && (
                error.message?.contains("connection", ignoreCase = true) == true ||
                    error.message?.contains("timeout", ignoreCase = true) == true
                )
}
