package com.mesh.wallet.data

import com.mesh.wallet.data.tron.TronWalletService

sealed class PhraseValidation {
    data object Empty : PhraseValidation()
    data object Valid : PhraseValidation()
    data class InvalidWordCount(val actual: Int) : PhraseValidation()
    data class InvalidWord(val position: Int, val value: String) : PhraseValidation()
    data object InvalidChecksum : PhraseValidation()
}

object MeshWalletRestore {
    val allowedMnemonicWordCounts = setOf(12, 15, 18, 21, 24)

    fun normalizePhrase(text: String): List<String> =
        text.trim()
            .lowercase()
            .split(Regex("\\s+"))
            .filter { it.isNotBlank() }

    fun sanitizedPhrasePaste(raw: String): String =
        normalizePhrase(raw.take(8_000)).take(24).joinToString(" ")

    fun validatePhrase(text: String): PhraseValidation {
        val words = normalizePhrase(text)
        if (words.isEmpty()) return PhraseValidation.Empty
        if (!allowedMnemonicWordCounts.contains(words.size)) {
            return PhraseValidation.InvalidWordCount(words.size)
        }
        for ((index, word) in words.withIndex()) {
            if (!Bip39Words.contains(word)) {
                return PhraseValidation.InvalidWord(index + 1, word)
            }
        }
        return runCatching { TronWalletService.importWallet(words) }
            .fold(
                onSuccess = { PhraseValidation.Valid },
                onFailure = { PhraseValidation.InvalidChecksum }
            )
    }

    fun normalizePrivateKeyInput(input: String): String =
        input.trim()
            .removePrefix("0x")
            .removePrefix("0X")
            .filter { !it.isWhitespace() }
            .lowercase()

    fun isValidPrivateKeyFormat(input: String): Boolean {
        val hex = normalizePrivateKeyInput(input)
        if (hex.length != 64) return false
        return hex.all { it in '0'..'9' || it in 'a'..'f' }
    }
}
