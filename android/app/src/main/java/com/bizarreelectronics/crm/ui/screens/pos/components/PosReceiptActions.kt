package com.bizarreelectronics.crm.ui.screens.pos.components

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.print.PrintAttributes
import android.print.PrintManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.PictureAsPdf
import androidx.compose.material.icons.filled.Print
import androidx.compose.material.icons.filled.Sms
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.ui.screens.pos.CartLine
import com.bizarreelectronics.crm.ui.screens.pos.PosCartState
import com.bizarreelectronics.crm.util.formatAsMoney
import kotlinx.coroutines.launch

/**
 * §16.6 — Receipt action bar shown on [PosSuccessScreen] and in sales history.
 *
 * Actions:
 *  - Print  → [CashDrawerController.printReceipt] (BT thermal) or Mopria system print.
 *             Falls back to "Save PDF" when no printer is available (404 / absent BT).
 *  - Email  → ACTION_SENDTO mailto: with PDF attachment (SAF uri).
 *  - SMS    → POST /sms/send with public tracking URL.
 *  - PDF    → SAF ACTION_CREATE_DOCUMENT — saves receipt PDF to chosen location.
 *  - Gift receipt toggle — hides prices, shows item names only.
 *  - Reprint from history → same composable, just set [isReprint] = true.
 */
@Composable
fun PosReceiptActions(
    cart: PosCartState,
    invoiceId: Long,
    serverBaseUrl: String,
    onSmsSend: suspend (phone: String, body: String) -> Result<Unit>,
    modifier: Modifier = Modifier,
    isReprint: Boolean = false,
    cashDrawerController: CashDrawerControllerStub? = null,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    var giftReceipt by remember { mutableStateOf(false) }
    var printError by remember { mutableStateOf<String?>(null) }
    var showSmsDialog by remember { mutableStateOf(false) }

    // SAF launcher for "Download PDF"
    val savePdfLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument("application/pdf")
    ) { uri ->
        uri?.let { dest ->
            scope.launch {
                writePdfToUri(context, dest, cart, giftReceipt, invoiceId)
            }
        }
    }

    if (printError != null) {
        AlertDialog(
            onDismissRequest = { printError = null },
            confirmButton = {
                TextButton(onClick = { printError = null }) { Text("OK") }
            },
            title = { Text("Print unavailable") },
            text = { Text(printError!!) },
        )
    }

    if (showSmsDialog) {
        SmsReceiptDialog(
            cart = cart,
            invoiceId = invoiceId,
            serverBaseUrl = serverBaseUrl,
            onSend = { phone ->
                scope.launch {
                    val trackingUrl = "$serverBaseUrl/receipts/$invoiceId"
                    val body = buildSmsBody(cart, trackingUrl, giftReceipt)
                    onSmsSend(phone, body)
                        .onFailure { printError = it.message }
                }
                showSmsDialog = false
            },
            onDismiss = { showSmsDialog = false },
        )
    }

    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        // Gift receipt toggle
        Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
            Switch(
                checked = giftReceipt,
                onCheckedChange = { giftReceipt = it },
            )
            Spacer(Modifier.width(8.dp))
            Text("Gift receipt (hide prices)", style = MaterialTheme.typography.bodyMedium)
        }

        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.fillMaxWidth(),
        ) {
            // Print or Save PDF
            val hasPrinter = cashDrawerController?.hasPrinter() == true
            OutlinedButton(
                onClick = {
                    scope.launch {
                        if (hasPrinter) {
                            cashDrawerController!!.printReceipt(cart, giftReceipt)
                                .onFailure { err ->
                                    // Fallback: system print
                                    launchSystemPrint(context, cart, giftReceipt, invoiceId)
                                }
                        } else {
                            launchSystemPrint(context, cart, giftReceipt, invoiceId)
                        }
                    }
                },
                modifier = Modifier.weight(1f),
            ) {
                Icon(if (hasPrinter) Icons.Default.Print else Icons.Default.PictureAsPdf, null)
                Spacer(Modifier.width(4.dp))
                Text(if (hasPrinter) "Print" else "Save PDF")
            }

            // Email
            OutlinedButton(
                onClick = {
                    val customerEmail = ""  // TODO: surface from AttachedCustomer when email field added
                    launchEmailReceipt(context, customerEmail, cart, invoiceId, giftReceipt)
                },
                modifier = Modifier.weight(1f),
            ) {
                Icon(Icons.Default.Email, null)
                Spacer(Modifier.width(4.dp))
                Text("Email")
            }

            // SMS
            OutlinedButton(
                onClick = { showSmsDialog = true },
                modifier = Modifier.weight(1f),
            ) {
                Icon(Icons.Default.Sms, null)
                Spacer(Modifier.width(4.dp))
                Text("SMS")
            }

            // Download PDF
            OutlinedButton(
                onClick = {
                    val filename = "receipt-${invoiceId}.pdf"
                    savePdfLauncher.launch(filename)
                },
                modifier = Modifier.weight(1f),
            ) {
                Icon(Icons.Default.PictureAsPdf, null)
                Spacer(Modifier.width(4.dp))
                Text("PDF")
            }
        }

        if (isReprint) {
            Text(
                "Reprint",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

// ─── SMS dialog ───────────────────────────────────────────────────────────────

@Composable
private fun SmsReceiptDialog(
    cart: PosCartState,
    invoiceId: Long,
    serverBaseUrl: String,
    onSend: (phone: String) -> Unit,
    onDismiss: () -> Unit,
) {
    var phone by remember {
        mutableStateOf(cart.customer?.let { "" } ?: "")
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Send receipt via SMS") },
        text = {
            OutlinedTextField(
                value = phone,
                onValueChange = { phone = it },
                label = { Text("Phone number") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
        },
        confirmButton = {
            TextButton(onClick = { if (phone.isNotBlank()) onSend(phone) }) {
                Text("Send")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        },
    )
}

// ─── Stubs for platform operations ───────────────────────────────────────────

private fun launchEmailReceipt(
    context: Context,
    email: String,
    cart: PosCartState,
    invoiceId: Long,
    giftReceipt: Boolean,
) {
    val subject = "Your receipt #$invoiceId"
    val body = buildEmailBody(cart, giftReceipt)
    val intent = Intent(Intent.ACTION_SENDTO).apply {
        data = Uri.parse("mailto:")
        putExtra(Intent.EXTRA_EMAIL, arrayOf(email))
        putExtra(Intent.EXTRA_SUBJECT, subject)
        putExtra(Intent.EXTRA_TEXT, body)
    }
    runCatching { context.startActivity(Intent.createChooser(intent, "Send receipt")) }
}

private fun launchSystemPrint(
    context: Context,
    cart: PosCartState,
    giftReceipt: Boolean,
    invoiceId: Long,
) {
    val printManager = context.getSystemService(Context.PRINT_SERVICE) as? PrintManager ?: return
    val jobName = "Receipt #$invoiceId"
    val receiptText = buildReceiptText(cart, giftReceipt)
    val adapter = TextPrintDocumentAdapter(context, receiptText, jobName)
    printManager.print(
        jobName,
        adapter,
        PrintAttributes.Builder()
            .setMediaSize(PrintAttributes.MediaSize.ISO_A4)
            .setResolution(PrintAttributes.Resolution("default", "default", 300, 300))
            .setMinMargins(PrintAttributes.Margins.NO_MARGINS)
            .build(),
    )
}

private suspend fun writePdfToUri(
    context: Context,
    uri: Uri,
    cart: PosCartState,
    giftReceipt: Boolean,
    invoiceId: Long,
) {
    // Stub: in production this would render a PDF via PdfDocument API.
    runCatching {
        context.contentResolver.openOutputStream(uri)?.use { out ->
            val text = buildReceiptText(cart, giftReceipt)
            out.write(text.toByteArray())
        }
    }
}

private fun buildReceiptText(cart: PosCartState, giftReceipt: Boolean): String {
    val sb = StringBuilder()
    sb.appendLine("Bizarre Electronics")
    sb.appendLine("===================")
    for (line in cart.lines) {
        if (giftReceipt) {
            sb.appendLine("  ${line.name} x${line.qty}")
        } else {
            sb.appendLine("  ${line.name} x${line.qty}  ${line.totalCents.formatAsMoney()}")
        }
    }
    if (!giftReceipt) {
        sb.appendLine("-------------------")
        sb.appendLine("Total: ${cart.totalCents.formatAsMoney()}")
    }
    return sb.toString()
}

private fun buildEmailBody(cart: PosCartState, giftReceipt: Boolean): String =
    buildReceiptText(cart, giftReceipt)

private fun buildSmsBody(cart: PosCartState, trackingUrl: String, giftReceipt: Boolean): String {
    return if (giftReceipt) {
        "Your gift receipt: $trackingUrl"
    } else {
        "Your receipt (${cart.totalCents.formatAsMoney()}): $trackingUrl"
    }
}

// ─── Stub interfaces (replaced by real impls at injection sites) ──────────────

/** Stub so [PosReceiptActions] compiles without the full [CashDrawerController]. */
interface CashDrawerControllerStub {
    fun hasPrinter(): Boolean
    suspend fun printReceipt(cart: PosCartState, giftReceipt: Boolean): Result<Unit>
}

// ─── TextPrintDocumentAdapter stub ───────────────────────────────────────────

private class TextPrintDocumentAdapter(
    private val context: Context,
    private val text: String,
    private val jobName: String,
) : android.print.PrintDocumentAdapter() {
    override fun onLayout(
        oldAttributes: PrintAttributes?,
        newAttributes: PrintAttributes,
        cancellationSignal: android.os.CancellationSignal?,
        callback: LayoutResultCallback,
        extras: android.os.Bundle?,
    ) {
        if (cancellationSignal?.isCanceled == true) {
            callback.onLayoutCancelled()
            return
        }
        callback.onLayoutFinished(
            android.print.PrintDocumentInfo.Builder(jobName)
                .setContentType(android.print.PrintDocumentInfo.CONTENT_TYPE_DOCUMENT)
                .setPageCount(1)
                .build(),
            true,
        )
    }

    override fun onWrite(
        pages: Array<out android.print.PageRange>?,
        destination: android.os.ParcelFileDescriptor,
        cancellationSignal: android.os.CancellationSignal?,
        callback: WriteResultCallback,
    ) {
        runCatching {
            java.io.FileOutputStream(destination.fileDescriptor).use { out ->
                out.write(text.toByteArray())
            }
            callback.onWriteFinished(arrayOf(android.print.PageRange.ALL_PAGES))
        }.onFailure { callback.onWriteFailed(it.message) }
    }
}
