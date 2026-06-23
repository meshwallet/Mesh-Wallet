package com.mesh.wallet.ui.components

import android.graphics.Bitmap
import android.graphics.Color
import androidx.compose.foundation.Image
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import com.google.zxing.BarcodeFormat
import com.google.zxing.qrcode.QRCodeWriter

@Composable
fun MeshQRCode(content: String, modifier: Modifier = Modifier) {
    val bitmap = remember(content) { generateQrBitmap(content) }
    Image(bitmap = bitmap.asImageBitmap(), contentDescription = "QR Code", modifier = modifier)
}

private fun generateQrBitmap(content: String, size: Int = 512): Bitmap {
    val matrix = QRCodeWriter().encode(content, BarcodeFormat.QR_CODE, size, size)
    val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.RGB_565)
    for (x in 0 until size) {
        for (y in 0 until size) {
            bmp.setPixel(x, y, if (matrix[x, y]) Color.BLACK else Color.WHITE)
        }
    }
    return bmp
}
