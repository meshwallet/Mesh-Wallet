package com.mesh.wallet.data.tron

import wallet.core.jni.Base58

object MeshABIEncoder {
    private val approveSelector = hexToBytes("095ea7b3")
    private val sendWithFeeSelector = hexToBytes("67156f76")

    fun encodeApproveCallData(spenderBase58: String, amount: Long = Long.MAX_VALUE): ByteArray {
        val parameter = encodeApproveParameter(spenderBase58, amount)
        return approveSelector + parameter
    }

    fun encodeSendWithFeeCallData(recipientBase58: String, recipientAmount: Long, feeAmount: Long): ByteArray {
        val parameter = encodeSendWithFeeParameter(recipientBase58, recipientAmount, feeAmount)
        return sendWithFeeSelector + parameter
    }

    fun encodeAllowanceParameter(ownerBase58: String, spenderBase58: String): String {
        val owner = TronAddressHex.addressWord(ownerBase58) ?: throw TronApiException.InvalidAddress
        val spender = TronAddressHex.addressWord(spenderBase58) ?: throw TronApiException.InvalidAddress
        return (owner + spender).toHex()
    }

    private fun encodeApproveParameter(spenderBase58: String, amount: Long): ByteArray {
        val spender = TronAddressHex.addressWord(spenderBase58) ?: throw TronApiException.InvalidAddress
        return spender + TronAmountEncoder.encodeUInt256(amount)
    }

    private fun encodeSendWithFeeParameter(recipientBase58: String, recipientAmount: Long, feeAmount: Long): ByteArray {
        val recipient = TronAddressHex.addressWord(recipientBase58) ?: throw TronApiException.InvalidAddress
        return recipient + TronAmountEncoder.encodeUInt256(recipientAmount) + TronAmountEncoder.encodeUInt256(feeAmount)
    }

    private fun hexToBytes(hex: String): ByteArray =
        hex.chunked(2).map { it.toInt(16).toByte() }.toByteArray()

    private fun ByteArray.toHex(): String = joinToString("") { "%02x".format(it) }
}

object TronAddressHex {
    fun addressWord(address: String): ByteArray? {
        val trimmed = address.trim()
        if (trimmed.isEmpty()) return null
        val payload = base58Payload(trimmed) ?: return null
        return wordFromBytes(payload)
    }

    private fun base58Payload(base58: String): ByteArray? {
        return runCatching {
            val decoded = Base58.decodeNoCheck(base58)
            if (decoded.size >= 21) decoded.copyOfRange(0, 21) else null
        }.getOrNull()
    }

    private fun wordFromBytes(raw: ByteArray): ByteArray? {
        val addressBytes = when {
            raw.size == 21 && raw[0] == 0x41.toByte() -> raw.copyOfRange(1, 21)
            raw.size == 20 -> raw
            else -> return null
        }
        if (addressBytes.size != 20) return null
        val word = ByteArray(32)
        addressBytes.copyInto(word, destinationOffset = 12)
        return word
    }
}
