package com.mesh.wallet.core

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context

object MeshClipboard {
    fun pasteString(context: Context, maxCharacters: Int = 12_000): String? {
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
        val text = clipboard?.primaryClip?.getItemAt(0)?.text?.toString()?.trim().orEmpty()
        if (text.isEmpty()) return null
        return text.take(maxCharacters)
    }

    fun copyString(context: Context, label: String, text: String): Boolean =
        runCatching {
            val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            clipboard.setPrimaryClip(ClipData.newPlainText(label, text))
            true
        }.getOrDefault(false)
}
