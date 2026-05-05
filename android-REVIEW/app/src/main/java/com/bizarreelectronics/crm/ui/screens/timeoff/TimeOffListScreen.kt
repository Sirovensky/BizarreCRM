package com.bizarreelectronics.crm.ui.screens.timeoff

import android.widget.Toast
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.BeachAccess
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState

private data class FilterOption(val label: String, val value: String?)
private val STATUS_FILTERS = listOf(
    FilterOption("Pending", "pending"),
    FilterOption("Approved", "approved"),
    FilterOption("Rejected", "rejected"),
    FilterOption("All", null),
)

/**
 * §48.3 Time-Off manager approval queue.
 *
 * Manager/Admin only screen. Shows all employee time-off requests filterable
 * by status. Each card has Approve / Reject actions with optional reason dialog.
 *
 * 404-tolerant: shows "not configured on this server" empty state.
 *
 * @param onBack Navigate back.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TimeOffListScreen(
    onBack: () -> Unit,
    viewModel: TimeOffViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current
    var pendingRejectId by remember { mutableStateOf<Long?>(null) }

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
                title = "Time-Off Requests",
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            // Status filter chips
            LazyRow(
                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(STATUS_FILTERS) { filter ->
                    FilterChip(
                        selected = state.statusFilter == filter.value,
                        onClick = { viewModel.setStatusFilter(filter.value) },
                        label = { Text(filter.label) },
                    )
                }
            }

            Box(modifier = Modifier.fillMaxSize()) {
                when {
                    state.isLoading -> CircularProgressIndicator(
                        modifier = Modifier.align(Alignment.Center),
                    )

                    state.serverUnsupported -> EmptyState(
                        icon = Icons.Default.BeachAccess,
                        title = "Time Off not available",
                        subtitle = "Time-off management is not configured on this server.",
                    )

                    state.error != null -> ErrorState(
                        message = state.error!!,
                        onRetry = { viewModel.refresh() },
                    )

                    state.requests.isEmpty() -> EmptyState(
                        icon = Icons.Default.BeachAccess,
                        title = "No requests",
                        subtitle = when (state.statusFilter) {
                            "pending" -> "No pending requests."
                            "approved" -> "No approved requests."
                            "rejected" -> "No rejected requests."
                            else -> "No time-off requests found."
                        },
                    )

                    else -> LazyColumn(
                        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                        modifier = Modifier.fillMaxSize(),
                    ) {
                        items(state.requests, key = { it.id }) { req ->
                            TimeOffRequestCard(
                                request = req,
                                showApproveReject = req.status == TimeOffStatus.Pending && state.isManager,
                                onApprove = { viewModel.approveRequest(req.id) },
                                onReject = { pendingRejectId = req.id },
                            )
                        }
                    }
                }
            }
        }
    }

    // Reject-with-reason dialog
    val rejectId = pendingRejectId
    if (rejectId != null) {
        RejectReasonDialog(
            onDismiss = { pendingRejectId = null },
            onConfirm = { reason ->
                viewModel.rejectRequest(rejectId, reason)
                pendingRejectId = null
            },
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun RejectReasonDialog(
    onDismiss: () -> Unit,
    onConfirm: (reason: String) -> Unit,
) {
    var reason by remember { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Reject Request") },
        text = {
            Column {
                Text("Provide an optional reason for the employee.")
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
            TextButton(onClick = { onConfirm(reason) }) { Text("Reject") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        },
    )
}
