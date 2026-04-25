package com.bizarreelectronics.crm.ui.screens.pos

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.pdf.PdfDocument
import android.net.Uri
import android.util.Log
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.ReceiptNotificationApi
import com.bizarreelectronics.crm.data.remote.api.SendReceiptEmailRequest
import com.bizarreelectronics.crm.data.remote.api.SendReceiptSmsRequest
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import retrofit2.HttpException
import java.io.File
import java.io.IOException
import javax.inject.Inject

// ─── UI state ─────────────────────────────────────────────────────────────────

data class PosReceiptUiState(
    val orderId: String = "",
    val invoiceId: Long? = null,
    val totalCents: Long = 0L,
    val customerName: String = "",
    val customerPhone: String? = null,
    val customerEmail: String? = null,
    val linkedTicketId: Long? = null,
    val trackingUrl: String? = null,
    val smsSentState: SendState = SendState.IDLE,
    val smsError: String? = null,
    val emailSentState: SendState = SendState.IDLE,
    val emailError: String? = null,
    val printSentState: SendState = SendState.IDLE,
    val snackbarMessage: String? = null,
    // Non-null when a cache PDF is ready and the caller should fire the email intent.
    val pendingEmailPdfUri: Uri? = null,
)

enum class SendState { IDLE, SENDING, SENT, ERROR }

@HiltViewModel
class PosReceiptViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val coordinator: PosCoordinator,
    private val receiptApi: ReceiptNotificationApi,
    private val cashDrawerController: CashDrawerControllerStub,
    @ApplicationContext private val appContext: Context,
) : ViewModel() {

    private val _uiState = MutableStateFlow(PosReceiptUiState())
    val uiState: StateFlow<PosReceiptUiState> = _uiState.asStateFlow()

    init {
        val orderIdArg = savedStateHandle.get<String>("orderId") ?: ""
        viewModelScope.launch {
            coordinator.session.collect { session ->
                _uiState.update {
                    it.copy(
                        orderId = session.completedOrderId ?: orderIdArg,
                        invoiceId = session.completedInvoiceId,
                        totalCents = session.totalCents,
                        customerName = session.customer?.name ?: "",
                        customerPhone = session.customer?.phone,
                        customerEmail = session.customer?.email,
                        linkedTicketId = session.linkedTicketId,
                        // Use server-supplied URL when available; fall back to
                        // client-built path only when the server didn't provide one.
                        trackingUrl = session.trackingUrl
                            ?: session.completedOrderId?.let { id -> "/track/$id" },
                    )
                }
            }
        }
    }

    // ─── Thermal print ────────────────────────────────────────────────────────

    /**
     * Builds a [PrintableReceipt] from current VM state and sends it to the
     * paired Bluetooth thermal printer via [CashDrawerControllerStub.printReceipt].
     * Shows a snackbar on success or failure.
     *
     * @param giftReceipt When true the printer omits line-item prices (gift mode).
     */
    fun printThermal(giftReceipt: Boolean = false) {
        val state = _uiState.value
        val receipt = buildPrintableReceipt(state)
        _uiState.update { it.copy(printSentState = SendState.SENDING) }
        viewModelScope.launch {
            cashDrawerController.printReceipt(receipt, giftReceipt)
                .onSuccess {
                    _uiState.update {
                        it.copy(
                            printSentState = SendState.SENT,
                            snackbarMessage = "Printed successfully",
                        )
                    }
                }
                .onFailure { e ->
                    val msg = e.message ?: "Print failed"
                    _uiState.update {
                        it.copy(
                            printSentState = SendState.ERROR,
                            snackbarMessage = "Print failed: $msg",
                        )
                    }
                }
        }
    }

    // ─── SAF PDF download ─────────────────────────────────────────────────────

    /**
     * Renders a PDF receipt into [uri] (chosen via SAF CreateDocument).
     * Uses [android.graphics.pdf.PdfDocument] — no third-party dependency.
     */
    fun downloadPdf(uri: Uri) {
        val state = _uiState.value
        viewModelScope.launch {
            val result = withContext(Dispatchers.IO) {
                runCatching { renderReceiptPdf(state, uri) }
            }
            result
                .onSuccess {
                    _uiState.update { it.copy(snackbarMessage = "Saved") }
                }
                .onFailure { e ->
                    _uiState.update { it.copy(snackbarMessage = "Failed: ${e.message}") }
                }
        }
    }

    // ─── Local email intent (via mail app) ───────────────────────────────────

    /**
     * Renders the receipt PDF to [cacheDir/receipts/<orderId>.pdf], then sets
     * [PosReceiptUiState.pendingEmailPdfUri] to a FileProvider URI so the screen
     * can fire the ACTION_SEND intent. The screen must call [clearPendingEmailUri]
     * after consuming the value.
     */
    fun prepareLocalEmailIntent() {
        val state = _uiState.value
        viewModelScope.launch {
            val result = withContext(Dispatchers.IO) {
                runCatching {
                    val dir = File(appContext.cacheDir, "receipts").apply { mkdirs() }
                    val file = File(dir, "${state.orderId.ifBlank { "receipt" }}.pdf")
                    renderReceiptPdfToFile(state, file)
                    file
                }
            }
            result
                .onSuccess { file ->
                    // Pass the plain file; screen wraps with FileProvider.getUriForFile.
                    _uiState.update {
                        it.copy(pendingEmailPdfUri = Uri.fromFile(file))
                    }
                }
                .onFailure { e ->
                    _uiState.update { it.copy(snackbarMessage = "Email prep failed: ${e.message}") }
                }
        }
    }

    fun clearPendingEmailUri() = _uiState.update { it.copy(pendingEmailPdfUri = null) }

    // ─── Server-side send paths ───────────────────────────────────────────────

    fun sendSms() {
        val phone = _uiState.value.customerPhone ?: return
        val invoiceId = _uiState.value.invoiceId ?: return
        _uiState.update { it.copy(smsSentState = SendState.SENDING, smsError = null) }

        viewModelScope.launch {
            runCatching {
                receiptApi.sendReceiptSms(SendReceiptSmsRequest(invoiceId = invoiceId, phone = phone))
            }.onSuccess {
                _uiState.update {
                    it.copy(smsSentState = SendState.SENT, snackbarMessage = "SMS sent to $phone")
                }
            }.onFailure { e ->
                val is404 = e is HttpException && e.code() == 404
                val message = if (is404) {
                    // POS-SMS-001: endpoint not yet deployed on this server version
                    Log.w("PosReceipt", "receipt_sms_unavailable: server returned 404 for send-receipt-sms")
                    "SMS receipt not yet available"
                } else {
                    e.message ?: "SMS failed"
                }
                _uiState.update {
                    it.copy(smsSentState = SendState.ERROR, smsError = message, snackbarMessage = "SMS failed: $message")
                }
            }
        }
    }

    fun sendEmail() {
        val email = _uiState.value.customerEmail ?: return
        val invoiceId = _uiState.value.invoiceId ?: return
        _uiState.update { it.copy(emailSentState = SendState.SENDING, emailError = null) }

        viewModelScope.launch {
            runCatching {
                receiptApi.sendReceiptEmail(SendReceiptEmailRequest(invoiceId = invoiceId, recipientEmail = email))
            }.onSuccess {
                _uiState.update {
                    it.copy(emailSentState = SendState.SENT, snackbarMessage = "Email sent to $email")
                }
            }.onFailure { e ->
                val message = e.message ?: "Email failed"
                _uiState.update {
                    it.copy(emailSentState = SendState.ERROR, emailError = message, snackbarMessage = "Email failed: $message")
                }
            }
        }
    }

    fun clearSnackbar() = _uiState.update { it.copy(snackbarMessage = null) }

    fun startNewSale() = coordinator.resetSession()

    // ─── Internal helpers ─────────────────────────────────────────────────────

    /** Converts current UI state into the hardware-layer [PrintableReceipt] model. */
    private fun buildPrintableReceipt(state: PosReceiptUiState): PrintableReceipt {
        // The coordinator's session lines are the authoritative source.
        // If the session was already reset (reprint from history), fall back to a
        // single summary line built from the invoice total.
        val sessionLines = coordinator.session.value.lines
        val lines = if (sessionLines.isNotEmpty()) {
            sessionLines.map { line ->
                PrintableLine(
                    name = line.name,
                    qty = line.qty,
                    totalCents = line.lineTotalCents,
                )
            }
        } else {
            listOf(PrintableLine(name = "Sale", qty = 1, totalCents = state.totalCents))
        }
        return PrintableReceipt(
            lines = lines,
            totalCents = state.totalCents,
            customerName = state.customerName.ifBlank { null },
            orderId = state.orderId.ifBlank { null },
        )
    }

    /**
     * Renders a receipt PDF to [uri] (SAF output stream variant).
     * Letter size (612×792 pt). Draws header, line items, and totals as text.
     */
    private fun renderReceiptPdf(state: PosReceiptUiState, uri: Uri) {
        val lines = coordinator.session.value.lines
        val doc = PdfDocument()
        val pageInfo = PdfDocument.PageInfo.Builder(612, 792, 1).create()
        val page = doc.startPage(pageInfo)
        drawReceiptOnCanvas(page.canvas, state, lines)
        doc.finishPage(page)
        appContext.contentResolver.openOutputStream(uri)?.use { out ->
            doc.writeTo(out)
        } ?: throw IOException("Could not open output stream for URI: $uri")
        doc.close()
    }

    /**
     * Renders a receipt PDF to [file] (cache-file variant used for email intent).
     */
    private fun renderReceiptPdfToFile(state: PosReceiptUiState, file: File) {
        val lines = coordinator.session.value.lines
        val doc = PdfDocument()
        val pageInfo = PdfDocument.PageInfo.Builder(612, 792, 1).create()
        val page = doc.startPage(pageInfo)
        drawReceiptOnCanvas(page.canvas, state, lines)
        doc.finishPage(page)
        file.outputStream().use { out -> doc.writeTo(out) }
        doc.close()
    }

    private fun drawReceiptOnCanvas(
        canvas: Canvas,
        state: PosReceiptUiState,
        sessionLines: List<CartLine>,
    ) {
        val titlePaint = Paint().apply { textSize = 18f; isFakeBoldText = true }
        val bodyPaint = Paint().apply { textSize = 13f }
        val smallPaint = Paint().apply { textSize = 11f }
        var y = 60f

        canvas.drawText("Bizarre Electronics", 40f, y, titlePaint); y += 28f
        canvas.drawText("Receipt — Invoice #${state.invoiceId ?: state.orderId}", 40f, y, smallPaint); y += 20f
        canvas.drawText("Customer: ${state.customerName}", 40f, y, smallPaint); y += 28f

        canvas.drawText("Item", 40f, y, bodyPaint)
        canvas.drawText("Qty", 360f, y, bodyPaint)
        canvas.drawText("Total", 460f, y, bodyPaint); y += 20f
        canvas.drawLine(40f, y, 572f, y, smallPaint); y += 16f

        val drawLines = if (sessionLines.isNotEmpty()) sessionLines else emptyList()
        for (line in drawLines) {
            canvas.drawText(line.name.take(36), 40f, y, bodyPaint)
            canvas.drawText("${line.qty}", 360f, y, bodyPaint)
            canvas.drawText(line.lineTotalCents.toDollarString(), 460f, y, bodyPaint)
            y += 20f
        }

        y += 8f
        canvas.drawLine(40f, y, 572f, y, smallPaint); y += 20f
        canvas.drawText("TOTAL: ${state.totalCents.toDollarString()}", 360f, y, titlePaint)
    }
}
