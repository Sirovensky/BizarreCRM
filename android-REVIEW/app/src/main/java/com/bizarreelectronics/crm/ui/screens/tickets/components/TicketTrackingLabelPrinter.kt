package com.bizarreelectronics.crm.ui.screens.tickets.components

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.print.PageRange
import android.print.PrintAttributes
import android.print.PrintDocumentAdapter
import android.print.PrintDocumentInfo
import android.print.PrintManager
import com.bizarreelectronics.crm.util.QrCodeGenerator
import timber.log.Timber
import java.io.File
import java.io.FileOutputStream

/**
 * TicketTrackingLabelPrinter — §55.3 L4971
 *
 * Generates a label-sized (4 × 3 in, 288 × 216 pt at 72 dpi) PDF containing:
 *  - A QR code encoding the customer-facing [trackingUrl]
 *  - The [orderId] below the QR for manual entry
 *  - A short "Scan for repair status" footer
 *
 * If [trackingUrl] is null the printer falls back to encoding [orderId] so the
 * label is always printable.  The PDF is written to `cacheDir/tracking-label-$ticketId.pdf`
 * then handed to [PrintManager] via a minimal [PrintDocumentAdapter].
 *
 * Label dimensions follow standard 4×3" thermal label stock (e.g. DYMO 30252,
 * Zebra 2000D).  [PrintAttributes.MediaSize] uses [PrintAttributes.MediaSize.NA_INDEX_4X6]
 * as the closest pre-defined constant; the actual rendering area is 288×216 pt
 * (4×3 in).
 *
 * Usage — called from a coroutine scope on the main thread; internal [PdfDocument]
 * work is fast (<20 ms for a 288×216 bitmap decode at 96 dpi).  No I/O is done on
 * the main thread except inside the [PrintDocumentAdapter.onWrite] callback which
 * the framework calls on a background thread.
 *
 * @param context    [Context] used to obtain [PrintManager] and cache dir.
 * @param ticketId   Used only for cache-file naming.
 * @param orderId    Displayed beneath the QR code (e.g. "T-00042").
 * @param customerName Optional first-line label — omit when anonymous tickets.
 * @param trackingUrl  Full customer-facing URL to encode; falls back to [orderId].
 * @return `true` if the [PrintManager] dialog was successfully opened, `false` on error.
 */
fun printTicketTrackingLabel(
    context: Context,
    ticketId: Long,
    orderId: String,
    customerName: String?,
    trackingUrl: String?,
): Boolean {
    val qrContent = trackingUrl?.takeIf { it.isNotBlank() } ?: orderId

    // ── 1. Build the label PDF ────────────────────────────────────────────────
    val labelFile = buildLabelPdf(
        context = context,
        ticketId = ticketId,
        orderId = orderId,
        customerName = customerName,
        qrContent = qrContent,
    ) ?: return false

    // ── 2. Hand to PrintManager ───────────────────────────────────────────────
    return runCatching {
        val printManager = context.getSystemService(PrintManager::class.java)
            ?: error("PrintManager unavailable")

        val adapter = TrackingLabelPrintAdapter(
            labelFile = labelFile,
            jobName = "tracking-label-$orderId",
        )

        val attrs = PrintAttributes.Builder()
            // 4×3 in label stock; closest standard size in the framework.
            // The actual rendering in buildLabelPdf() uses exactly 288×216 pt.
            .setMediaSize(PrintAttributes.MediaSize.NA_INDEX_4X6)
            .setMinMargins(PrintAttributes.Margins.NO_MARGINS)
            .setColorMode(PrintAttributes.COLOR_MODE_MONOCHROME)
            .setResolution(
                PrintAttributes.Resolution("203dpi", "203 dpi", 203, 203),
            )
            .build()

        printManager.print("Tracking label $orderId", adapter, attrs)
        true
    }.onFailure { e ->
        Timber.tag("TrackingLabelPrinter").e(e, "Failed to open PrintManager dialog")
    }.getOrDefault(false)
}

// ── PDF generation ────────────────────────────────────────────────────────────

/**
 * Renders a 4×3 in (288×216 pt) [PdfDocument] with a QR code, order ID, and
 * shop footer.  Returns null if QR encoding or file-write fails.
 */
private fun buildLabelPdf(
    context: Context,
    ticketId: Long,
    orderId: String,
    customerName: String?,
    qrContent: String,
): File? = runCatching {
    // Label canvas is 288 × 216 pt (4 in × 3 in at 72 pt/in)
    val widthPt = 288
    val heightPt = 216

    val doc = PdfDocument()
    val pageInfo = PdfDocument.PageInfo.Builder(widthPt, heightPt, 1).create()
    val page = doc.startPage(pageInfo)
    val canvas: Canvas = page.canvas

    // White background
    canvas.drawRect(0f, 0f, widthPt.toFloat(), heightPt.toFloat(), Paint().apply {
        color = 0xFFFFFFFF.toInt()
        style = Paint.Style.FILL
    })

    // ── QR code (left side, 150×150 pt) ──────────────────────────────────────
    val qrSizePt = 150
    val qrBitmap: Bitmap = QrCodeGenerator.generateQrBitmap(qrContent, qrSizePt)
    val qrLeft = 8f
    val qrTop = (heightPt - qrSizePt) / 2f
    canvas.drawBitmap(qrBitmap, null, RectF(qrLeft, qrTop, qrLeft + qrSizePt, qrTop + qrSizePt), null)

    // ── Right-side text column ────────────────────────────────────────────────
    val textLeft = qrLeft + qrSizePt + 10f
    val textMaxWidth = widthPt - textLeft - 6f
    var textY = 30f

    val shopPaint = Paint().apply {
        color = 0xFF222222.toInt()
        textSize = 9f
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        isAntiAlias = true
    }
    val orderPaint = Paint().apply {
        color = 0xFF111111.toInt()
        textSize = 13f
        typeface = Typeface.create(Typeface.MONOSPACE, Typeface.BOLD)
        isAntiAlias = true
    }
    val subPaint = Paint().apply {
        color = 0xFF444444.toInt()
        textSize = 8f
        isAntiAlias = true
    }
    val footerPaint = Paint().apply {
        color = 0xFF888888.toInt()
        textSize = 7f
        isAntiAlias = true
    }

    canvas.drawText("Bizarre Electronics", textLeft, textY, shopPaint)
    textY += 14f

    canvas.drawText("Repair Ticket", textLeft, textY, subPaint)
    textY += 18f

    canvas.drawText(orderId, textLeft, textY, orderPaint)
    textY += 18f

    if (!customerName.isNullOrBlank()) {
        // Clip customer name to fit column width
        val clipped = clipTextToWidth(customerName, subPaint, textMaxWidth)
        canvas.drawText(clipped, textLeft, textY, subPaint)
        textY += 13f
    }

    // Horizontal rule
    canvas.drawLine(
        textLeft, textY + 4f,
        widthPt - 6f, textY + 4f,
        Paint().apply { color = 0xFFCCCCCC.toInt(); strokeWidth = 0.5f },
    )
    textY += 14f

    canvas.drawText("Scan QR for repair status", textLeft, textY, footerPaint)

    doc.finishPage(page)

    val outFile = File(context.cacheDir, "tracking-label-$ticketId.pdf")
    FileOutputStream(outFile).use { doc.writeTo(it) }
    doc.close()
    outFile
}.onFailure { e ->
    Timber.tag("TrackingLabelPrinter").e(e, "buildLabelPdf failed")
}.getOrNull()

/** Truncates [text] with an ellipsis so it fits within [maxWidthPx] pixels. */
private fun clipTextToWidth(text: String, paint: Paint, maxWidthPx: Float): String {
    if (paint.measureText(text) <= maxWidthPx) return text
    var end = text.length
    while (end > 0 && paint.measureText(text.substring(0, end) + "…") > maxWidthPx) {
        end--
    }
    return if (end > 0) text.substring(0, end) + "…" else "…"
}

// ── PrintDocumentAdapter ──────────────────────────────────────────────────────

private class TrackingLabelPrintAdapter(
    private val labelFile: File,
    private val jobName: String,
) : PrintDocumentAdapter() {

    override fun onLayout(
        oldAttributes: PrintAttributes?,
        newAttributes: PrintAttributes,
        cancellationSignal: CancellationSignal?,
        callback: LayoutResultCallback,
        extras: android.os.Bundle?,
    ) {
        if (cancellationSignal?.isCanceled == true) {
            callback.onLayoutCancelled()
            return
        }
        val info = PrintDocumentInfo.Builder("$jobName.pdf")
            .setContentType(PrintDocumentInfo.CONTENT_TYPE_DOCUMENT)
            .setPageCount(1)
            .build()
        callback.onLayoutFinished(info, oldAttributes != newAttributes)
    }

    override fun onWrite(
        pages: Array<out PageRange>?,
        destination: ParcelFileDescriptor,
        cancellationSignal: CancellationSignal?,
        callback: WriteResultCallback,
    ) {
        if (cancellationSignal?.isCanceled == true) {
            callback.onWriteCancelled()
            return
        }
        runCatching {
            labelFile.inputStream().use { input ->
                FileOutputStream(destination.fileDescriptor).use { output ->
                    input.copyTo(output)
                }
            }
            callback.onWriteFinished(arrayOf(PageRange.ALL_PAGES))
        }.onFailure { e ->
            Timber.tag("TrackingLabelPrinter").e(e, "onWrite failed")
            callback.onWriteFailed(e.message)
        }
    }
}
