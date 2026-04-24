package com.bizarreelectronics.crm.ui.screens.timeoff

import android.widget.Toast
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.BeachAccess
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SuggestionChip
import androidx.compose.material3.SuggestionChipDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState

/**
 * §48.3 Time-Off Request screen — staff view.
 *
 * Shows the current user's own time-off requests with their status chips.
 * FAB opens the submission dialog.
 *
 * 404-tolerant: shows "not configured on this server" empty state.
 *
 * @param onBack Navigate back.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TimeOffRequestScreen(
    onBack: () -> Unit,
    viewModel: TimeOffViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current

    LaunchedEffect(state.toastMessage) {
        val msg = state.toastMessage
        if (!msg.isNullOrBlank()) {
            Toast.makeText(context, msg, Toast.LENGTH_SHORT).show()
            viewModel.clearToast()
        }
    }

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Time Off",
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
        floatingActionButton = {
            FloatingActionButton(onClick = { viewModel.showRequestDialog() }) {
                Icon(Icons.Default.Add, contentDescription = "Request time off")
            }
        },
    ) { padding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            when {
                state.isLoading -> CircularProgressIndicator(modifier = Modifier.align(Alignment.Center))

                state.serverUnsupported -> EmptyState(
                    icon = Icons.Default.BeachAccess,
                    title = "Time Off not available",
                    subtitle = "Time-off requests are not configured on this server.",
                )

                state.error != null -> ErrorState(
                    message = state.error!!,
                    onRetry = { viewModel.refresh() },
                )

                state.requests.isEmpty() -> EmptyState(
                    icon = Icons.Default.BeachAccess,
                    title = "No requests yet",
                    subtitle = "Tap + to submit a time-off request.",
                )

                else -> LazyColumn(
                    contentPadding = PaddingValues(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                    modifier = Modifier.fillMaxSize(),
                ) {
                    items(state.requests, key = { it.id }) { req ->
                        TimeOffRequestCard(
                            request = req,
                            showCancelButton = req.status == TimeOffStatus.Pending,
                            onCancel = { viewModel.cancelRequest(req.id) },
                        )
                    }
                }
            }
        }
    }

    if (state.showRequestDialog) {
        SubmitRequestDialog(
            onDismiss = { viewModel.dismissRequestDialog() },
            onConfirm = { start, end, type, reason ->
                viewModel.submitRequest(start, end, type, reason)
            },
        )
    }
}

@Composable
internal fun TimeOffRequestCard(
    request: TimeOffRequest,
    showCancelButton: Boolean = false,
    showApproveReject: Boolean = false,
    onCancel: (() -> Unit)? = null,
    onApprove: (() -> Unit)? = null,
    onReject: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    Card(modifier = modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Top,
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    if (request.employeeName.isNotBlank()) {
                        Text(
                            text = request.employeeName,
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.SemiBold,
                        )
                    }
                    Text(
                        text = "${request.startDate.take(10)} → ${request.endDate.take(10)}",
                        style = MaterialTheme.typography.bodyMedium,
                    )
                    Text(
                        text = request.type.replaceFirstChar { it.uppercaseChar() },
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                StatusChip(status = request.status)
            }
            if (request.reason.isNotBlank()) {
                Spacer(Modifier.height(6.dp))
                Text(
                    text = request.reason,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (request.managerReason.isNotBlank()) {
                Spacer(Modifier.height(4.dp))
                Text(
                    text = "Manager: ${request.managerReason}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                )
            }
            if (showCancelButton || showApproveReject) {
                Spacer(Modifier.height(8.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (showCancelButton && onCancel != null) {
                        TextButton(onClick = onCancel) {
                            Icon(Icons.Default.Cancel, contentDescription = null)
                            Text("Cancel")
                        }
                    }
                    if (showApproveReject) {
                        if (onApprove != null) {
                            Button(onClick = onApprove) { Text("Approve") }
                        }
                        if (onReject != null) {
                            TextButton(onClick = onReject) { Text("Reject") }
                        }
                    }
                }
            }
        }
    }
}

@Composable
internal fun StatusChip(status: TimeOffStatus) {
    val (label, color) = when (status) {
        TimeOffStatus.Pending -> "Pending" to Color(0xFFFFA726)
        TimeOffStatus.Approved -> "Approved" to Color(0xFF4CAF50)
        TimeOffStatus.Rejected -> "Rejected" to Color(0xFFF44336)
        TimeOffStatus.Cancelled -> "Cancelled" to MaterialTheme.colorScheme.outline
    }
    SuggestionChip(
        onClick = {},
        label = { Text(label, style = MaterialTheme.typography.labelSmall) },
        colors = SuggestionChipDefaults.suggestionChipColors(
            containerColor = color.copy(alpha = 0.15f),
            labelColor = color,
        ),
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SubmitRequestDialog(
    onDismiss: () -> Unit,
    onConfirm: (startDate: String, endDate: String, type: TimeOffType, reason: String) -> Unit,
) {
    var startDate by remember { mutableStateOf("") }
    var endDate by remember { mutableStateOf("") }
    var selectedType by remember { mutableStateOf(TimeOffType.Vacation) }
    var reason by remember { mutableStateOf("") }
    var typeExpanded by remember { mutableStateOf(false) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Request Time Off") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = startDate,
                    onValueChange = { startDate = it },
                    label = { Text("Start Date (YYYY-MM-DD)") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = endDate,
                    onValueChange = { endDate = it },
                    label = { Text("End Date (YYYY-MM-DD)") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                ExposedDropdownMenuBox(
                    expanded = typeExpanded,
                    onExpandedChange = { typeExpanded = it },
                ) {
                    OutlinedTextField(
                        value = selectedType.label,
                        onValueChange = {},
                        readOnly = true,
                        label = { Text("Type") },
                        trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = typeExpanded) },
                        modifier = Modifier
                            .fillMaxWidth()
                            .menuAnchor(),
                    )
                    ExposedDropdownMenu(
                        expanded = typeExpanded,
                        onDismissRequest = { typeExpanded = false },
                    ) {
                        TimeOffType.entries.forEach { t ->
                            DropdownMenuItem(
                                text = { Text(t.label) },
                                onClick = { selectedType = t; typeExpanded = false },
                            )
                        }
                    }
                }
                OutlinedTextField(
                    value = reason,
                    onValueChange = { reason = it },
                    label = { Text("Reason (optional)") },
                    minLines = 2,
                    maxLines = 3,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        },
        confirmButton = {
            TextButton(onClick = { onConfirm(startDate, endDate, selectedType, reason) }) {
                Text("Submit")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        },
    )
}
