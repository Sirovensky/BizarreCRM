package com.bizarreelectronics.crm.ui.screens.invoices.components

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.print.PrintAttributes
import android.print.PrintManager
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.Print
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Sms
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp

/**
 * Send/share/print action buttons for an invoice detail screen.
 *
 * - "SMS"   → opens the native SMS app pre-filled with the invoice URL.
 * - "Email" → opens the native email app via ACTION_SENDTO/mailto:.
 * - "Share" → shares a plain-text summary + URL via ACTION_SEND.
 * - "Print" → opens system PrintManager (no bitmap required).
 *
 * All actions use Android Intents so they work offline (the server URL is
 * still embedded; the recipient views it when online). When [serverUrl] is
 * null or blank, the SMS / Email / Share body omits the link gracefully.
 */
@Composable
fun InvoiceSendActions(
    invoiceNumber: String,
    customerPhone: String?,
    customerEmail: String?,
    serverUrl: String?,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val invoiceLink = if (!serverUrl.isNullOrBlank()) "$serverUrl/invoices/$invoiceNumber" else null

    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            // SMS
            OutlinedButton(
                onClick = { sendSms(context, customerPhone, invoiceNumber, invoiceLink) },
                modifier = Modifier.weight(1f),
                enabled = !customerPhone.isNullOrBlank(),
            ) {
                Icon(
                    Icons.Default.Sms,
                    contentDescription = null,
                    modifier = Modifier.align(Alignment.CenterVertically),
                )
                Text("SMS", modifier = Modifier.align(Alignment.CenterVertically))
            }

            // Email
            OutlinedButton(
                onClick = { sendEmail(context, customerEmail, invoiceNumber, invoiceLink) },
                modifier = Modifier.weight(1f),
                enabled = !customerEmail.isNullOrBlank(),
            ) {
                Icon(
                    Icons.Default.Email,
                    contentDescription = null,
                    modifier = Modifier.align(Alignment.CenterVertically),
                )
                Text("Email", modifier = Modifier.align(Alignment.CenterVertically))
            }
        }
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            // Share
            OutlinedButton(
                onClick = { shareText(context, invoiceNumber, invoiceLink) },
                modifier = Modifier.weight(1f),
            ) {
                Icon(
                    Icons.Default.Share,
                    contentDescription = null,
                    modifier = Modifier.align(Alignment.CenterVertically),
                )
                Text("Share", modifier = Modifier.align(Alignment.CenterVertically))
            }

            // Print
            OutlinedButton(
                onClick = { printInvoice(context, invoiceNumber, invoiceLink) },
                modifier = Modifier.weight(1f),
            ) {
                Icon(
                    Icons.Default.Print,
                    contentDescription = null,
                    modifier = Modifier.align(Alignment.CenterVertically),
                )
                Text("Print", modifier = Modifier.align(Alignment.CenterVertically))
            }
        }
    }
}

// ── Intent helpers — kept as plain functions so they can be called from
//    DropdownMenuItem callbacks without a Composable context. ────────────────

/**
 * Opens the native SMS composer pre-filled with the invoice link.
 */
fun sendSms(context: Context, phone: String?, invoiceNumber: String, invoiceLink: String?) {
    val target = phone?.filter { it.isDigit() || it == '+' } ?: return
    val body = buildString {
        append("Your invoice #$invoiceNumber from Bizarre Electronics is ready.")
        if (invoiceLink != null) append("\n$invoiceLink")
    }
    val intent = Intent(Intent.ACTION_VIEW, Uri.parse("sms:$target"))
        .putExtra("sms_body", body)
    runCatching { context.startActivity(intent) }
}

/**
 * Opens the native email composer pre-filled with the invoice link.
 */
fun sendEmail(context: Context, email: String?, invoiceNumber: String, invoiceLink: String?) {
    val target = email ?: return
    val subject = "Invoice #$invoiceNumber – Bizarre Electronics"
    val body = buildString {
        append("Hi,\n\nYour invoice #$invoiceNumber from Bizarre Electronics is ready.")
        if (invoiceLink != null) append("\n\nView it here: $invoiceLink")
        append("\n\nThank you!")
    }
    val intent = Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:$target"))
        .putExtra(Intent.EXTRA_SUBJECT, subject)
        .putExtra(Intent.EXTRA_TEXT, body)
    runCatching { context.startActivity(Intent.createChooser(intent, "Send email")) }
}

/**
 * Shares a plain-text invoice summary via the Android share sheet.
 */
fun shareText(context: Context, invoiceNumber: String, invoiceLink: String?) {
    val text = buildString {
        append("Invoice #$invoiceNumber – Bizarre Electronics")
        if (invoiceLink != null) append("\n$invoiceLink")
    }
    val intent = Intent(Intent.ACTION_SEND)
        .setType("text/plain")
        .putExtra(Intent.EXTRA_TEXT, text)
    runCatching { context.startActivity(Intent.createChooser(intent, "Share invoice")) }
}

/**
 * Opens the system [PrintManager] to print an HTML representation of the invoice.
 *
 * Uses a WebViewPrintDocumentAdapter pattern: we build minimal HTML and let the
 * system's PDF renderer handle pagination. Falls back gracefully if the print
 * service is unavailable.
 */
fun printInvoice(context: Context, invoiceNumber: String, invoiceLink: String?) {
    runCatching {
        val printManager = context.getSystemService(Context.PRINT_SERVICE) as? PrintManager ?: return
        val html = buildString {
            append("<html><body>")
            append("<h1>Invoice #$invoiceNumber</h1>")
            append("<p>Bizarre Electronics</p>")
            if (invoiceLink != null) append("<p><a href=\"$invoiceLink\">$invoiceLink</a></p>")
            append("</body></html>")
        }
        val adapter = android.webkit.WebView(context).let { wv ->
            wv.loadDataWithBaseURL(null, html, "text/html", "UTF-8", null)
            wv.createPrintDocumentAdapter("Invoice_$invoiceNumber")
        }
        printManager.print(
            "Invoice_$invoiceNumber",
            adapter,
            PrintAttributes.Builder().build(),
        )
    }
}
