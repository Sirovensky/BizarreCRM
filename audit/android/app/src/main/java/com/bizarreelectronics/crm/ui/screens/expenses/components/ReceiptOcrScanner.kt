package com.bizarreelectronics.crm.ui.screens.expenses.components

import android.content.Context
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import java.util.Locale
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/** Structured result from a receipt OCR pass. All fields are nullable — OCR is best-effort. */
data class OcrReceiptResult(
    val total: String?,
    val vendor: String?,
    val date: String?,
)

/**
 * ML Kit Text Recognition wrapper (on-device Latin, no Firebase).
 *
 * Usage: call [scanReceipt] from a coroutine. Returns [OcrReceiptResult] on success,
 * or throws an exception on failure (callers should fall back to manual entry).
 */
object ReceiptOcrScanner {

    private val recognizer by lazy {
        TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
    }

    /**
     * Loads [uri] as a bitmap, runs ML Kit text recognition on it, then applies
     * regex heuristics to extract {total, vendor, date}.
     *
     * Caller is responsible for catching exceptions and falling back to manual entry.
     */
    suspend fun scanReceipt(context: Context, uri: Uri): OcrReceiptResult {
        val bitmap = withContext(Dispatchers.IO) { loadBitmap(context, uri) }
        val text = runRecognizer(bitmap)
        return parseReceiptText(text)
    }

    private fun loadBitmap(context: Context, uri: Uri): Bitmap {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            ImageDecoder.decodeBitmap(ImageDecoder.createSource(context.contentResolver, uri)) { decoder, _, _ ->
                decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            }
        } else {
            @Suppress("DEPRECATION")
            MediaStore.Images.Media.getBitmap(context.contentResolver, uri)
        }
    }

    private suspend fun runRecognizer(bitmap: Bitmap): String {
        val image = InputImage.fromBitmap(bitmap, 0)
        return suspendCancellableCoroutine { cont ->
            recognizer.process(image)
                .addOnSuccessListener { result -> cont.resume(result.text) }
                .addOnFailureListener { e -> cont.resumeWithException(e) }
        }
    }

    /**
     * Pure regex parser — extracted so it can be unit-tested without ML Kit.
     * Order of precedence: last matching line wins (receipts put total at the bottom).
     */
    internal fun parseReceiptText(rawText: String): OcrReceiptResult {
        val lines = rawText.lines()

        // Total: look for "total" keyword followed by a dollar/decimal amount
        // Regex: optional 'total'/'amount'/'due' keyword, then $XX.XX
        val totalRegex = Regex(
            """(?i)(?:total|amount\s+due|balance\s+due|grand\s+total)[^\d$]*[$]?\s*(\d{1,6}[.,]\d{2})""",
        )
        // Fallback: any standalone dollar amount on a "total" line
        val amountFallbackRegex = Regex("""(?i)\btotal\b.*?(\d{1,6}[.,]\d{2})""")

        var total: String? = null
        for (line in lines) {
            totalRegex.find(line)?.let { total = it.groupValues[1].replace(",", ".") }
            if (total == null) amountFallbackRegex.find(line)?.let { total = it.groupValues[1].replace(",", ".") }
        }

        // Vendor: first non-blank, non-numeric line (usually the header)
        val vendor = lines.firstOrNull { line ->
            line.isNotBlank() && line.any { it.isLetter() } && !line.matches(Regex("^\\d.*"))
        }?.trim()?.take(60)

        // Date: ISO-like (YYYY-MM-DD), US slash (MM/DD/YYYY or M/D/YY), or written month
        val dateRegex = Regex(
            """(?i)(\d{4}[-/]\d{2}[-/]\d{2}|\d{1,2}/\d{1,2}/\d{2,4}|(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+\d{1,2},?\s+\d{4})""",
        )
        var date: String? = null
        for (line in lines) {
            dateRegex.find(line)?.let { date = it.groupValues[1] }
        }

        return OcrReceiptResult(
            total = total,
            vendor = vendor,
            date = date,
        )
    }
}
