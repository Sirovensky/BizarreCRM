package com.bizarreelectronics.crm.util

import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import com.google.mlkit.vision.barcode.BarcodeScanner
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage

/**
 * §17.2 — ML Kit barcode analyzer.
 *
 * Wraps [BarcodeScanning.getClient] with ALL barcode formats enabled.
 * Intended for use as an [ImageAnalysis.Analyzer] in a CameraX analysis use-case.
 *
 * Formats explicitly supported: Code128, Code39, EAN-13, UPC-A, UPC-E,
 * QR, DataMatrix, ITF (all covered by [Barcode.FORMAT_ALL_FORMATS]).
 *
 * Thread safety: [analyze] is called on the analysis executor thread;
 * [onBarcodeDetected] callback is invoked on that same thread — callers must
 * post to the main thread if they update UI state.
 */
class BarcodeAnalyzer(
    private val onBarcodeDetected: (String, Int) -> Unit,
) : ImageAnalysis.Analyzer {

    private val options: BarcodeScannerOptions = BarcodeScannerOptions.Builder()
        .setBarcodeFormats(Barcode.FORMAT_ALL_FORMATS)
        .build()

    private val scanner: BarcodeScanner = BarcodeScanning.getClient(options)

    // Throttle: skip analysis while a previous frame is still being processed.
    @Volatile
    private var isProcessing = false

    override fun analyze(imageProxy: ImageProxy) {
        if (isProcessing) {
            imageProxy.close()
            return
        }
        isProcessing = true

        val mediaImage = imageProxy.image
        if (mediaImage == null) {
            imageProxy.close()
            isProcessing = false
            return
        }

        val inputImage = InputImage.fromMediaImage(
            mediaImage,
            imageProxy.imageInfo.rotationDegrees,
        )

        scanner.process(inputImage)
            .addOnSuccessListener { barcodes ->
                barcodes.firstOrNull { !it.rawValue.isNullOrBlank() }?.let { barcode ->
                    onBarcodeDetected(barcode.rawValue!!, barcode.format)
                }
            }
            .addOnCompleteListener {
                // Always close the proxy to unblock the next frame.
                imageProxy.close()
                isProcessing = false
            }
    }

    fun close() {
        scanner.close()
    }

    companion object {
        /**
         * Converts an ML Kit [Barcode.FORMAT_*] constant to a human-readable
         * format name for display in the UI scan result overlay.
         */
        fun formatName(format: Int): String = when (format) {
            Barcode.FORMAT_CODE_128    -> "Code 128"
            Barcode.FORMAT_CODE_39     -> "Code 39"
            Barcode.FORMAT_CODE_93     -> "Code 93"
            Barcode.FORMAT_EAN_13      -> "EAN-13"
            Barcode.FORMAT_EAN_8       -> "EAN-8"
            Barcode.FORMAT_UPC_A       -> "UPC-A"
            Barcode.FORMAT_UPC_E       -> "UPC-E"
            Barcode.FORMAT_QR_CODE     -> "QR Code"
            Barcode.FORMAT_DATA_MATRIX -> "DataMatrix"
            Barcode.FORMAT_ITF         -> "ITF"
            Barcode.FORMAT_AZTEC       -> "Aztec"
            Barcode.FORMAT_PDF417      -> "PDF417"
            else                       -> "Unknown"
        }
    }
}
