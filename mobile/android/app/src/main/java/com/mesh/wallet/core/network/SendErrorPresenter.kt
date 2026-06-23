package com.mesh.wallet.core.network

object SendErrorPresenter {
    const val rateLimitUserMessage =
        "Tron network is busy. Please wait about a minute and try again."

    fun containsRateLimitSignal(text: String): Boolean {
        val lower = text.lowercase()
        return "429" in lower || "rate limit" in lower || "too many requests" in lower ||
            "too many subrequests" in lower
    }

    fun messageFor(error: Throwable): String {
        if (containsRateLimitSignal(error.message.orEmpty())) return rateLimitUserMessage
        val text = error.message.orEmpty()
        if (text.contains("connection", ignoreCase = true)) {
            return "Network is unavailable. Check your connection and try again."
        }
        if (text.contains("timeout", ignoreCase = true)) {
            return "Mesh send service timed out. Check your connection and try again."
        }
        return userFacingRelayText(text.ifBlank { "Mesh send service is temporarily unavailable. Please try again." })
    }

    fun relayFailureMessage(raw: String, httpStatus: Int? = null): String {
        if (httpStatus == 429) return rateLimitUserMessage
        return userFacingRelayText(raw)
    }

    fun userFacingRelayText(raw: String): String {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return "Mesh send service is temporarily unavailable. Please try again."
        if (isHtmlPayload(trimmed)) return htmlPayloadMessage(trimmed)
        if (containsRateLimitSignal(trimmed)) return rateLimitUserMessage
        if (trimmed.length > 240) return "Mesh send service is temporarily unavailable. Please try again."

        val kvMessage = kvWriteLimitMessage(trimmed)
        if (kvMessage != null) return kvMessage

        if (trimmed.startsWith("{")) {
            val messageRegex = """"message"\s*:\s*"([^"]+)"""".toRegex()
            val message = messageRegex.find(trimmed)?.groupValues?.getOrNull(1)
            if (!message.isNullOrEmpty()) {
                return when (message) {
                    "feeUSDT invalid" -> "Send service rejected the request. Please try again."
                    else -> kvWriteLimitMessage(message) ?: message
                }
            }
            return "Mesh send service rejected the request. Please try again."
        }
        return trimmed
    }

    private fun isHtmlPayload(text: String): Boolean {
        val lower = text.lowercase()
        return "<!doctype html" in lower || "<html" in lower || "cloudflare" in lower ||
            "worker threw exception" in lower
    }

    private fun htmlPayloadMessage(html: String): String {
        return if ("worker threw exception" in html.lowercase()) {
            "Mesh send service hit an error. Please try again in a few minutes."
        } else {
            "Mesh send service is temporarily unavailable. Please try again."
        }
    }

    private fun kvWriteLimitMessage(text: String): String? {
        val lower = text.lowercase()
        return if ("kv put" in lower && "limit exceeded" in lower) {
            "Mesh send service is at capacity for today. Please try again tomorrow."
        } else null
    }
}
