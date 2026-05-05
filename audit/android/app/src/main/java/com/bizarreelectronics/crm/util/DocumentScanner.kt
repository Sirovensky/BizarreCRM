package com.bizarreelectronics.crm.util

import android.app.Activity
import android.content.IntentSender
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.IntentSenderRequest
import com.google.mlkit.vision.documentscanner.GmsDocumentScanner
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions
import com.google.mlkit.vision.documentscanner.GmsDocumentScanning
import com.google.mlkit.vision.documentscanner.GmsDocumentScanningResult

/**
 * §17.3 — GMS Document Scanning wrapper.
 *
 * Wraps [GmsDocumentScanning.getClient] with the FULL scanner mode so the
 * user gets ML-powered edge detection and perspective correction.
 *
 * Usage:
 * 1. Call [getScanner] to retrieve a configured scanner.
 * 2. Call [startScan] with the Activity and the [ActivityResultLauncher]
 *    registered in the composable via [rememberLauncherForActivityResult].
 * 3. In the launcher callback, call [handleResult] to extract the PDF URI
 *    from [GmsDocumentScanningResult] and hand it to the upload worker.
 *
 * Use cases: waivers, warranty cards, receipts, customer IDs.
 */
object DocumentScanner {

    /**
     * Returns a configured [GmsDocumentScanner] for full-mode scanning.
     *
     * Full mode includes ML edge detection, perspective correction, and
     * multi-page support (up to [pageLimit] pages, default 10).
     */
    fun getScanner(pageLimit: Int = 10): GmsDocumentScanner {
        val options = GmsDocumentScannerOptions.Builder()
            .setScannerMode(GmsDocumentScannerOptions.SCANNER_MODE_FULL)
            .setPageLimit(pageLimit)
            .setResultFormats(
                GmsDocumentScannerOptions.RESULT_FORMAT_PDF,
                GmsDocumentScannerOptions.RESULT_FORMAT_JPEG,
            )
            .setGalleryImportAllowed(true)
            .build()
        return GmsDocumentScanning.getClient(options)
    }

    /**
     * Starts the document scan intent. Retrieves the [IntentSender] from the
     * GMS scanner and launches it via [launcher]. Any error is surfaced via
     * [onError] so the caller can show a graceful "scanner unavailable" message.
     */
    fun startScan(
        activity: Activity,
        scanner: GmsDocumentScanner,
        launcher: ActivityResultLauncher<IntentSenderRequest>,
        onError: (Exception) -> Unit,
    ) {
        scanner.getStartScanIntent(activity)
            .addOnSuccessListener { intentSender ->
                launcher.launch(IntentSenderRequest.Builder(intentSender).build())
            }
            .addOnFailureListener { e ->
                onError(e)
            }
    }

    /**
     * Extracts the PDF URI from a completed [GmsDocumentScanningResult].
     *
     * Returns null when the result contains no PDF (e.g. the user cancelled).
     * The returned URI is a content:// URI valid within the calling app process;
     * pass it to WorkManager / MultipartUploadWorker for background upload.
     */
    fun pdfUriFromResult(result: GmsDocumentScanningResult): android.net.Uri? {
        return result.pdf?.uri
    }

    /**
     * Extracts all JPEG page URIs from the scan result.
     * Useful when the caller wants individual page images rather than a PDF.
     */
    fun jpegUrisFromResult(result: GmsDocumentScanningResult): List<android.net.Uri> {
        return result.pages?.mapNotNull { it.imageUri } ?: emptyList()
    }
}
