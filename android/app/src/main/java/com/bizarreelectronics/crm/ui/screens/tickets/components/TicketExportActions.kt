package com.bizarreelectronics.crm.ui.screens.tickets.components

import android.content.Context
import android.net.Uri
import android.util.Log
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Download
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.platform.LocalContext
import com.bizarreelectronics.crm.data.local.db.entities.TicketEntity
import com.bizarreelectronics.crm.ui.screens.tickets.TicketListUiState
import com.bizarreelectronics.crm.ui.screens.tickets.applySortOrder
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit

private const val TAG = "TicketExportActions"

// -----------------------------------------------------------------------
// CSV export — overflow menu item
// -----------------------------------------------------------------------

/**
 * Overflow [DropdownMenuItem] that triggers an SAF "Create Document" picker for CSV export.
 * Launches SAF → builds CSV from current filtered+sorted list in VM state → writes to URI.
 *
 * @param state      Current [TicketListUiState] — provides filtered + sorted ticket list.
 * @param onDismiss  Called after the item is tapped (to close the overflow menu).
 */
@Composable
fun ExportCsvMenuItem(
    state: TicketListUiState,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    val launcher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.CreateDocument("text/csv"),
    ) { uri: Uri? ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            writeCsv(context, uri, state)
        }
    }

    val timestamp = DateTimeFormatter.ofPattern("yyyyMMdd").format(LocalDate.now())

    DropdownMenuItem(
        text = { Text("Export CSV") },
        onClick = {
            onDismiss()
            launcher.launch("tickets_$timestamp.csv")
        },
        leadingIcon = {
            Icon(Icons.Default.Download, contentDescription = null)
        },
    )
}

// -----------------------------------------------------------------------
// CSV builder — pure function, tested separately
// -----------------------------------------------------------------------

/** Build CSV content from [state]'s current filtered+sorted ticket list. */
fun buildCsvContent(state: TicketListUiState): String {
    val tickets = applySortOrder(state.tickets, state.currentSort)
    val today = LocalDate.now()
    val sb = StringBuilder()
    sb.appendLine("id,created_at,customer,device,status,assignee,total,urgency,age_days")
    for (ticket in tickets) {
        sb.appendLine(ticketToCsvRow(ticket, today))
    }
    return sb.toString()
}

private fun ticketToCsvRow(ticket: TicketEntity, today: LocalDate): String {
    val ageDays = ticketAgeDays(ticket.createdAt, today) ?: ""
    val urgency = ticketUrgencyFor(ticket).label
    val totalFormatted = "%.2f".format(ticket.total / 100.0)
    return listOf(
        ticket.id,
        csvEscape(ticket.createdAt),
        csvEscape(ticket.customerName ?: ""),
        csvEscape(ticket.firstDeviceName ?: ""),
        csvEscape(ticket.statusName ?: ""),
        ticket.assignedTo?.toString() ?: "",
        totalFormatted,
        urgency,
        ageDays,
    ).joinToString(",")
}

/** Wrap a field in quotes and escape internal double-quotes per RFC 4180. */
private fun csvEscape(value: String): String {
    val escaped = value.replace("\"", "\"\"")
    return "\"$escaped\""
}

// -----------------------------------------------------------------------
// SAF writer
// -----------------------------------------------------------------------

private suspend fun writeCsv(context: Context, uri: Uri, state: TicketListUiState) {
    withContext(Dispatchers.IO) {
        try {
            val csv = buildCsvContent(state)
            context.contentResolver.openOutputStream(uri)?.use { stream ->
                stream.write(csv.toByteArray(Charsets.UTF_8))
            }
            Log.d(TAG, "CSV exported: ${state.tickets.size} rows → $uri")
        } catch (e: Exception) {
            Log.e(TAG, "CSV export failed: ${e.message}", e)
        }
    }
}
