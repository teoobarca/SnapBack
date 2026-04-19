package com.snapback.mobile.pair

import android.Manifest
import android.content.pm.PackageManager
import android.os.Bundle
import android.util.Size
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.layout.*
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import com.snapback.mobile.security.KeystoreTokenStore
import com.snapback.mobile.service.MobileForegroundService
import java.util.concurrent.Executors

class PairingActivity : ComponentActivity() {

    private val cameraExecutor = Executors.newSingleThreadExecutor()

    private val requestCameraPermission = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (!granted) {
            Toast.makeText(this, "Camera permission required to scan the QR", Toast.LENGTH_LONG).show()
            finish()
        } else {
            setContent { ScannerUI() }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA)
            == PackageManager.PERMISSION_GRANTED) {
            setContent { ScannerUI() }
        } else {
            requestCameraPermission.launch(Manifest.permission.CAMERA)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        cameraExecutor.shutdown()
    }

    @Composable
    private fun ScannerUI() {
        var statusText by remember { mutableStateOf("Point the camera at the QR code on your Mac") }

        Box(modifier = Modifier.fillMaxSize()) {
            AndroidView(
                factory = { ctx ->
                    val preview = PreviewView(ctx)
                    bindCamera(preview) { result ->
                        onPaired(result)
                        statusText = "Paired. You can return to your Mac."
                    }
                    preview
                },
                modifier = Modifier.fillMaxSize()
            )
            Text(
                statusText,
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(24.dp)
            )
        }
    }

    private fun bindCamera(view: PreviewView, onResult: (PairingResult) -> Unit) {
        val providerFuture = ProcessCameraProvider.getInstance(this)
        providerFuture.addListener({
            val provider = providerFuture.get()
            val preview = Preview.Builder().build().also {
                it.setSurfaceProvider(view.surfaceProvider)
            }
            val options = BarcodeScannerOptions.Builder()
                .setBarcodeFormats(Barcode.FORMAT_QR_CODE)
                .build()
            val scanner = BarcodeScanning.getClient(options)
            val analyzer = ImageAnalysis.Builder()
                .setTargetResolution(Size(1280, 720))
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .build()
                .also { it.setAnalyzer(cameraExecutor) { proxy -> scan(scanner, proxy, onResult) } }

            provider.unbindAll()
            provider.bindToLifecycle(
                this, CameraSelector.DEFAULT_BACK_CAMERA, preview, analyzer
            )
        }, ContextCompat.getMainExecutor(this))
    }

    @androidx.camera.core.ExperimentalGetImage
    private fun scan(
        scanner: com.google.mlkit.vision.barcode.BarcodeScanner,
        proxy: ImageProxy,
        onResult: (PairingResult) -> Unit
    ) {
        val media = proxy.image
        if (media == null) { proxy.close(); return }
        val input = InputImage.fromMediaImage(media, proxy.imageInfo.rotationDegrees)
        scanner.process(input)
            .addOnSuccessListener { barcodes ->
                for (b in barcodes) {
                    val raw = b.rawValue ?: continue
                    val pr = PairingResult.parse(raw) ?: continue
                    onResult(pr)
                    return@addOnSuccessListener
                }
            }
            .addOnCompleteListener { proxy.close() }
    }

    private fun onPaired(result: PairingResult) {
        KeystoreTokenStore(this).write(result.token)
        MobileForegroundService.start(this)
        runOnUiThread {
            Toast.makeText(this, "Paired with ${result.deskName}", Toast.LENGTH_SHORT).show()
            finish()
        }
    }
}
