package com.mesh.wallet.ui.send

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.common.InputImage
import com.mesh.wallet.core.l10n.L10n
import com.mesh.wallet.data.tron.TronUSDTService
import com.mesh.wallet.ui.components.MeshCloseButton
import com.mesh.wallet.ui.theme.MeshColors
import com.mesh.wallet.ui.theme.MeshMetrics
import com.mesh.wallet.ui.theme.MeshTypography
import java.util.concurrent.Executors

@Composable
fun TronQRScannerSheet(
    visible: Boolean,
    onDismiss: () -> Unit,
    onScanned: (String) -> Unit
) {
    if (!visible) return
    val context = LocalContext.current
    var hasPermission by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
        )
    }
    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted -> hasPermission = granted }

    LaunchedEffect(Unit) {
        if (!hasPermission) permissionLauncher.launch(Manifest.permission.CAMERA)
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(MeshColors.Background)
    ) {
        if (hasPermission) {
            QrScannerContent(onScanned = { raw ->
                val address = parseTronAddress(raw)
                if (address != null) {
                    onScanned(address)
                    onDismiss()
                }
            })
        } else {
            Text(
                "Camera permission required for QR scanning.",
                color = MeshColors.TextSecondary,
                modifier = Modifier.align(Alignment.Center)
            )
        }
        MeshCloseButton(
            onClick = onDismiss,
            modifier = Modifier
                .align(Alignment.TopStart)
                .padding(MeshMetrics.ScreenPadding)
        )
        Text(
            text = L10n.tr(context, "send_scan_qr"),
            style = MeshTypography.ScreenTitle,
            color = MeshColors.TextPrimary,
            modifier = Modifier
                .align(Alignment.TopCenter)
                .padding(top = 72.dp)
        )
    }
}

@Composable
private fun QrScannerContent(onScanned: (String) -> Unit) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    var handled by remember { mutableStateOf(false) }

    AndroidView(
        factory = { ctx ->
            val previewView = PreviewView(ctx)
            val cameraProviderFuture = ProcessCameraProvider.getInstance(ctx)
            cameraProviderFuture.addListener({
                val cameraProvider = cameraProviderFuture.get()
                val preview = Preview.Builder().build().also {
                    it.surfaceProvider = previewView.surfaceProvider
                }
                val analyzer = ImageAnalysis.Builder()
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .build()
                val scanner = BarcodeScanning.getClient()
                analyzer.setAnalyzer(Executors.newSingleThreadExecutor()) { imageProxy ->
                    val mediaImage = imageProxy.image
                    if (mediaImage != null && !handled) {
                        val image = InputImage.fromMediaImage(mediaImage, imageProxy.imageInfo.rotationDegrees)
                        scanner.process(image)
                            .addOnSuccessListener { barcodes ->
                                val value = barcodes.firstOrNull()?.rawValue
                                if (!value.isNullOrBlank() && !handled) {
                                    handled = true
                                    onScanned(value)
                                }
                            }
                            .addOnCompleteListener { imageProxy.close() }
                    } else {
                        imageProxy.close()
                    }
                }
                cameraProvider.unbindAll()
                cameraProvider.bindToLifecycle(
                    lifecycleOwner,
                    CameraSelector.DEFAULT_BACK_CAMERA,
                    preview,
                    analyzer
                )
            }, ContextCompat.getMainExecutor(ctx))
            previewView
        },
        modifier = Modifier.fillMaxSize()
    )
}

private fun parseTronAddress(raw: String): String? {
    val trimmed = raw.trim()
    if (TronUSDTService.isValidTronAddress(trimmed)) return trimmed
    val tronUri = Regex("tron:(T[1-9A-HJ-NP-Za-km-z]{33})", RegexOption.IGNORE_CASE).find(trimmed)
    return tronUri?.groupValues?.getOrNull(1)
}
