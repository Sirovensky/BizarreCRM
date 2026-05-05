package com.bizarreelectronics.crm.ui.screens.reports.components

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.print.PrintAttributes
import android.print.PrintManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.FileDownload
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Print
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.OutputStreamWriter

/**
 * Overflow menu icon for the Reports top-app-bar: Export CSV (SAF) and Print (PrintManager).
 *
 * Pattern mirrors [InvoiceSendActions] (ActionPlan §15 L1724):
 *   - Export CSV: uses SAF ACTION_CREATE_DOCUMENT to let the user pick a save location.
 *   - Export PDF / Print: uses PrintManager + WebView (same pattern as printInvoice).
 *
 * [csvContent] is a lambda so the caller can defer CSV generation until the user
 * actually taps Export — avoids building a potentially large string on every
 * recomposition.
 *
 * [reportTitle] is used as the default filename stem and the print job name.
 */
@Composable
fun ReportsExportActions(
    reportTitle: String,
    csvContent: () -> String,
    printHtmlContent: () -> String = { "<html><body><h1>$reportTitle</h1></body></html>" },
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var expanded by remember { mutableStateOf(false) }

    val safLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.CreateDocument("text/csv"),
    ) { uri: Uri? ->
        if (uri != null) {
            scope.launch {
                writeUriCsv(context, uri, csvContent())
            }
        }
    }

    IconButton(onClick = { expanded = true }) {
        Icon(Icons.Default.MoreVert, contentDescription = "Export options")
    }

    DropdownMenu(
        expanded = expanded,
        onDismissRequest = { expanded = false },
    ) {
        DropdownMenuItem(
            text = { Text("Export CSV") },
            leadingIcon = { Icon(Icons.Default.FileDownload, contentDescription = null) },
            onClick = {
                expanded = false
                val safeName = "${reportTitle.replace(' ', '_')}.csv"
                safLauncher.launch(safeName)
            },
        )
        DropdownMenuItem(
            text = { Text("Print / Export PDF") },
            leadingIcon = { Icon(Icons.Default.Print, contentDescription = null) },
            onClick = {
                expanded = false
                printReport(context, reportTitle, printHtmlContent())
            },
        )
    }
}

// ─── Intent / system helpers ─────────────────────────────────────────────────

private suspend fun writeUriCsv(context: Context, uri: Uri, csv: String) {
    withContext(Dispatchers.IO) {
        runCatching {
            context.contentResolver.openOutputStream(uri)?.use { stream ->
                OutputStreamWriter(stream, Charsets.UTF_8).use { writer ->
                    writer.write(csv)
                }
            }
        }
    }
}

/**
 * Opens the system [PrintManager] with a lightweight HTML document.
 *
 * Reuses the same WebView pattern from [printInvoice] in InvoiceSendActions.
 */
fun printReport(context: Context, reportTitle: String, html: String) {
    runCatching {
        val printManager = context.getSystemService(Context.PRINT_SERVICE) as? PrintManager ?: return
        val adapter = android.webkit.WebView(context).let { wv ->
            wv.loadDataWithBaseURL(null, html, "text/html", "UTF-8", null)
            wv.createPrintDocumentAdapter(reportTitle)
        }
        printManager.print(
            reportTitle,
            adapter,
            PrintAttributes.Builder().build(),
        )
    }
}
