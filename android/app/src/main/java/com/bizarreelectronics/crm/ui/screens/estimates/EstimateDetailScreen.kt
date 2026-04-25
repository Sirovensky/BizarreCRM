package com.bizarreelectronics.crm.ui.screens.estimates

import android.content.Context
import android.print.PrintAttributes
import android.print.PrintManager
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.data.local.db.entities.EstimateEntity
import com.bizarreelectronics.crm.data.remote.api.EstimateVersion
import com.bizarreelectronics.crm.ui.components.shared.BrandCard
import com.bizarreelectronics.crm.ui.components.shared.BrandStatusBadge
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.ConfirmDialog
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.ui.components.shared.LoadingIndicator
import com.bizarreelectronics.crm.ui.screens.invoices.components.sendEmail
import com.bizarreelectronics.crm.ui.screens.invoices.components.sendSms
import com.bizarreelectronics.crm.util.formatAsMoney
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EstimateDetailScreen(
    estimateId: Long,
    onBack: () -> Unit,
    onConverted: (ticketId: Long) -> Unit,
    // AND-20260414-M7: invoked after a successful delete. Nav graph uses this
    // to write a refresh signal into the previous back stack entry and pop.
    onDeleted: (() -> Unit)? = null,
    viewModel: EstimateDetailViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val estimate = state.estimate
    val context = LocalContext.current

    val snackbarHostState = remember { SnackbarHostState() }
    var showMenu by remember { mutableStateOf(false) }
    var showDeleteConfirm by remember { mutableStateOf(false) }
    var showExpireConfirm by remember { mutableStateOf(false) }
    var showSendSheet by remember { mutableStateOf(false) }
    val sendSheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    LaunchedEffect(state.actionMessage) {
        state.actionMessage?.let { message ->
            snackbarHostState.showSnackbar(message)
            viewModel.clearActionMessage()
        }
    }

    LaunchedEffect(state.convertedTicketId) {
        val ticketId = state.convertedTicketId
        if (ticketId != null) {
            onConverted(ticketId)
            viewModel.clearConvertedTicket()
        }
    }

    // 8.4: sync expire confirm from VM state (overflow menu delegates to VM)
    LaunchedEffect(state.showExpireConfirm) {
        showExpireConfirm = state.showExpireConfirm
    }

    // AND-20260414-M7: navigate back once delete succeeds.
    LaunchedEffect(state.deletedCounter) {
        if (state.deletedCounter > 0) {
            onDeleted?.invoke() ?: onBack()
        }
    }

    // L1332 — reject dialog with required reason field
    if (state.showRejectDialog) {
        AlertDialog(
            onDismissRequest = { viewModel.onRejectDismissed() },
            title = { Text("Reject Estimate") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Please provide a reason for rejection.")
                    OutlinedTextField(
                        value = state.rejectReason,
                        onValueChange = { viewModel.onRejectReasonChanged(it) },
                        label = { Text("Reason *") },
                        modifier = Modifier.fillMaxWidth(),
                        minLines = 2,
                        isError = state.rejectReason.isBlank(),
                        supportingText = {
                            if (state.rejectReason.isBlank()) Text("Required")
                        },
                    )
                }
            },
            confirmButton = {
                TextButton(
                    onClick = { viewModel.rejectEstimate() },
                    enabled = state.rejectReason.isNotBlank(),
                ) { Text("Reject", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = {
                TextButton(onClick = { viewModel.onRejectDismissed() }) { Text("Cancel") }
            },
        )
    }

    // L1331 — approve confirm dialog
    if (state.showApproveConfirm) {
        ConfirmDialog(
            title = "Approve Estimate",
            message = "Mark this estimate as approved?",
            confirmLabel = "Approve",
            onConfirm = { viewModel.approveEstimate() },
            onDismiss = { viewModel.onApproveDismissed() },
        )
    }

    if (showDeleteConfirm) {
        ConfirmDialog(
            title = "Delete Estimate",
            message = "Are you sure you want to delete this estimate? This action cannot be undone.",
            confirmLabel = "Delete",
            onConfirm = {
                showDeleteConfirm = false
                viewModel.delete()
            },
            onDismiss = { showDeleteConfirm = false },
            isDestructive = true,
        )
    }

    // 8.4 — Mark as expired confirm
    if (showExpireConfirm) {
        ConfirmDialog(
            title = "Mark as Expired",
            message = "Mark this estimate as expired? The customer will need a new revision.",
            confirmLabel = "Mark Expired",
            onConfirm = {
                showExpireConfirm = false
                viewModel.markAsExpired()
            },
            onDismiss = {
                showExpireConfirm = false
                viewModel.onMarkExpiredDismissed()
            },
            isDestructive = false,
        )
    }

    // L1330 — send bottom sheet: SMS / Email with pre-filled body
    if (showSendSheet) {
        ModalBottomSheet(
            onDismissRequest = { showSendSheet = false },
            sheetState = sendSheetState,
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(16.dp)
                    .navigationBarsPadding(),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Text("Send Estimate", style = MaterialTheme.typography.titleMedium)
                HorizontalDivider()
                val estimateNum = estimate?.orderId?.ifBlank { "EST-$estimateId" } ?: "EST-$estimateId"
                val phone = estimate?.let { null } // customerPhone not on entity; intent helper handles null
                val email = estimate?.let { null } // customerEmail not on entity; intent helper handles null
                val estimateUrl = "Your estimate #$estimateNum from Bizarre Electronics"
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    OutlinedButton(
                        onClick = {
                            showSendSheet = false
                            // API-side send
                            viewModel.sendViaSms()
                            // Also open native SMS composer pre-filled
                            sendSms(context, phone, estimateNum, null)
                        },
                        modifier = Modifier.weight(1f),
                    ) {
                        Icon(Icons.Default.Sms, contentDescription = null)
                        Spacer(Modifier.width(4.dp))
                        Text("SMS")
                    }
                    OutlinedButton(
                        onClick = {
                            showSendSheet = false
                            viewModel.sendViaEmail()
                            sendEmail(context, email, estimateNum, null)
                        },
                        modifier = Modifier.weight(1f),
                    ) {
                        Icon(Icons.Default.Email, contentDescription = null)
                        Spacer(Modifier.width(4.dp))
                        Text("Email")
                    }
                }
                Spacer(Modifier.height(8.dp))
            }
        }
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            BrandTopAppBar(
                title = estimate?.orderId?.ifBlank { "EST-$estimateId" } ?: "EST-$estimateId",
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    Box {
                        IconButton(onClick = { showMenu = true }) {
                            Icon(Icons.Default.MoreVert, contentDescription = "More")
                        }
                        DropdownMenu(
                            expanded = showMenu,
                            onDismissRequest = { showMenu = false },
                        ) {
                            DropdownMenuItem(
                                text = { Text("Send") },
                                leadingIcon = { Icon(Icons.AutoMirrored.Filled.Send, contentDescription = null) },
                                onClick = { showMenu = false; showSendSheet = true },
                            )
                            DropdownMenuItem(
                                text = { Text("Approve") },
                                leadingIcon = { Icon(Icons.Default.CheckCircle, contentDescription = null) },
                                onClick = { showMenu = false; viewModel.onApproveRequested() },
                            )
                            DropdownMenuItem(
                                text = { Text("Reject") },
                                leadingIcon = { Icon(Icons.Default.ThumbDown, contentDescription = null) },
                                onClick = { showMenu = false; viewModel.onRejectRequested() },
                            )
                            DropdownMenuItem(
                                text = { Text("Convert to invoice") },
                                leadingIcon = { Icon(Icons.Default.Receipt, contentDescription = null) },
                                onClick = { showMenu = false; viewModel.convertToInvoice() },
                            )
                            // L1336 — print
                            if (estimate != null) {
                                DropdownMenuItem(
                                    text = { Text("Print / PDF") },
                                    leadingIcon = { Icon(Icons.Default.Print, contentDescription = null) },
                                    onClick = {
                                        showMenu = false
                                        printEstimate(
                                            context = context,
                                            estimateNumber = estimate.orderId.ifBlank { "EST-${estimate.id}" },
                                            customerName = estimate.customerName,
                                            total = estimate.total,
                                        )
                                    },
                                )
                            }
                            DropdownMenuItem(
                                text = { Text("Mark as expired") },
                                leadingIcon = { Icon(Icons.Default.Timer, contentDescription = null) },
                                onClick = {
                                    showMenu = false
                                    viewModel.onMarkExpiredRequested()
                                },
                                enabled = estimate != null &&
                                    !estimate.status.equals("expired", ignoreCase = true),
                            )
                            DropdownMenuItem(
                                text = { Text("Delete", color = MaterialTheme.colorScheme.error) },
                                leadingIcon = {
                                    Icon(
                                        Icons.Default.Delete,
                                        contentDescription = null,
                                        tint = MaterialTheme.colorScheme.error,
                                    )
                                },
                                onClick = { showMenu = false; showDeleteConfirm = true },
                            )
                        }
                    }
                },
            )
        },
    ) { padding ->
        when {
            state.isLoading -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    LoadingIndicator()
                }
            }
            state.error != null -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    ErrorState(
                        message = state.error ?: "Error",
                        onRetry = { viewModel.loadEstimate() },
                    )
                }
            }
            estimate != null -> {
                EstimateDetailContent(
                    estimate = estimate,
                    isActionInProgress = state.isActionInProgress,
                    versions = state.versions,
                    selectedVersionIndex = state.selectedVersionIndex,
                    versionNumber = state.versionNumber,
                    lineItems = state.lineItems,
                    padding = padding,
                    onConvertToTicket = { viewModel.convertToTicket() },
                    onConvertToInvoice = { viewModel.convertToInvoice() },
                    onSend = { showSendSheet = true },
                    onApprove = { viewModel.onApproveRequested() },
                    onReject = { viewModel.onRejectRequested() },
                    onVersionSelected = { viewModel.onVersionSelected(it) },
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun EstimateDetailContent(
    estimate: EstimateEntity,
    isActionInProgress: Boolean,
    versions: List<EstimateVersion>,
    selectedVersionIndex: Int,
    /** Version number from the latest API response — shown as "v{n}" in header. */
    versionNumber: Int,
    lineItems: List<com.bizarreelectronics.crm.data.remote.dto.EstimateLineItem>,
    padding: PaddingValues,
    onConvertToTicket: () -> Unit,
    onConvertToInvoice: () -> Unit,
    onSend: () -> Unit,
    onApprove: () -> Unit,
    onReject: () -> Unit,
    onVersionSelected: (Int) -> Unit,
) {
    val alreadyConverted = estimate.convertedTicketId != null ||
        estimate.status.equals("converted", ignoreCase = true)

    // 8.4 — expiration banner: show when status == expired or validUntil < today
    val isExpired = estimate.status.equals("expired", ignoreCase = true) || run {
        val v = estimate.validUntil ?: return@run false
        runCatching {
            val expiryDate = LocalDate.parse(v.take(10), DateTimeFormatter.ISO_LOCAL_DATE)
            expiryDate.isBefore(LocalDate.now())
        }.getOrDefault(false)
    }

    // Human-readable valid-until string
    val validUntilFormatted: String? = estimate.validUntil?.take(10)?.let { iso ->
        runCatching {
            val d = LocalDate.parse(iso, DateTimeFormatter.ISO_LOCAL_DATE)
            d.format(DateTimeFormatter.ofPattern("MMM d, yyyy", Locale.getDefault()))
        }.getOrDefault(iso)
    }

    val estimateNumber = estimate.orderId.ifBlank { "EST-${estimate.id}" }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(padding),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // 8.2 Header card: Estimate #{number} · v{version}, status SuggestionChip, valid-until
        item {
            BrandCard(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    // Top row: large estimate number + version label
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            "Estimate #$estimateNumber",
                            style = MaterialTheme.typography.titleLarge,
                            fontWeight = FontWeight.Bold,
                        )
                        Text(
                            "v$versionNumber",
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    // Status SuggestionChip
                    SuggestionChip(
                        onClick = {},
                        label = {
                            Text(
                                estimate.status.replaceFirstChar { it.uppercase() },
                                style = MaterialTheme.typography.labelMedium,
                            )
                        },
                        colors = SuggestionChipDefaults.suggestionChipColors(
                            containerColor = when {
                                estimate.status.equals("approved", ignoreCase = true) ->
                                    MaterialTheme.colorScheme.primaryContainer
                                estimate.status.equals("rejected", ignoreCase = true) ||
                                    estimate.status.equals("expired", ignoreCase = true) ->
                                    MaterialTheme.colorScheme.errorContainer
                                else -> MaterialTheme.colorScheme.secondaryContainer
                            },
                            labelColor = when {
                                estimate.status.equals("approved", ignoreCase = true) ->
                                    MaterialTheme.colorScheme.onPrimaryContainer
                                estimate.status.equals("rejected", ignoreCase = true) ||
                                    estimate.status.equals("expired", ignoreCase = true) ->
                                    MaterialTheme.colorScheme.onErrorContainer
                                else -> MaterialTheme.colorScheme.onSecondaryContainer
                            },
                        ),
                        border = null,
                    )
                    // Valid-until row
                    if (validUntilFormatted != null) {
                        Text(
                            "Valid until $validUntilFormatted",
                            style = MaterialTheme.typography.bodySmall,
                            color = if (isExpired)
                                MaterialTheme.colorScheme.error
                            else
                                MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    Text(
                        "Created: ${estimate.createdAt.take(10)}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    if (estimate.convertedTicketId != null) {
                        Text(
                            "Converted to ticket #${estimate.convertedTicketId}",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.primary,
                        )
                    }
                }
            }
        }

        // 8.4 Expiration banner
        if (isExpired) {
            item {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.errorContainer,
                    ),
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(12.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(
                            Icons.Default.Timer,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onErrorContainer,
                            modifier = Modifier.size(18.dp),
                        )
                        Text(
                            "This estimate has expired. Send a new revision?",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onErrorContainer,
                            modifier = Modifier.weight(1f),
                        )
                    }
                }
            }
        }

        // L1335 — Version dropdown (only when server returns versions)
        if (versions.isNotEmpty()) {
            item {
                VersionDropdown(
                    versions = versions,
                    selectedIndex = selectedVersionIndex,
                    onVersionSelected = onVersionSelected,
                )
            }
        }

        // Customer card
        item {
            BrandCard(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Text(
                        "Customer",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        estimate.customerName ?: "Unknown",
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold,
                    )
                }
            }
        }

        // 8.2 Line items
        if (lineItems.isNotEmpty()) {
            item {
                BrandCard(modifier = Modifier.fillMaxWidth()) {
                    Column(
                        modifier = Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Text(
                            "Line Items",
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.3f))
                        // Header row
                        Row(modifier = Modifier.fillMaxWidth()) {
                            Text(
                                "Description",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.weight(1f),
                            )
                            Text(
                                "Qty",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.width(36.dp),
                            )
                            Text(
                                "Unit",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.width(64.dp),
                            )
                            Text(
                                "Total",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.width(72.dp),
                                fontWeight = FontWeight.SemiBold,
                            )
                        }
                        lineItems.forEach { item ->
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                verticalAlignment = Alignment.Top,
                            ) {
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(
                                        item.description ?: item.itemName ?: "-",
                                        style = MaterialTheme.typography.bodySmall,
                                    )
                                    if (!item.itemSku.isNullOrBlank()) {
                                        Text(
                                            "SKU: ${item.itemSku}",
                                            style = MaterialTheme.typography.labelSmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        )
                                    }
                                }
                                Text(
                                    "${item.quantity ?: 1}",
                                    style = MaterialTheme.typography.bodySmall,
                                    modifier = Modifier.width(36.dp),
                                )
                                Text(
                                    "$%.2f".format(item.unitPrice ?: 0.0),
                                    style = MaterialTheme.typography.bodySmall,
                                    modifier = Modifier.width(64.dp),
                                )
                                Text(
                                    "$%.2f".format(item.total ?: 0.0),
                                    style = MaterialTheme.typography.bodySmall,
                                    fontWeight = FontWeight.SemiBold,
                                    modifier = Modifier.width(72.dp),
                                )
                            }
                        }
                    }
                }
            }
        }

        // Pricing breakdown
        item {
            BrandCard(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Text(
                        "Pricing",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Text("Subtotal", style = MaterialTheme.typography.bodyMedium)
                        Text(estimate.subtotal.formatAsMoney(), style = MaterialTheme.typography.bodyMedium)
                    }
                    if (estimate.discount > 0) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                        ) {
                            Text("Discount", style = MaterialTheme.typography.bodyMedium)
                            Text(
                                "-${estimate.discount.formatAsMoney()}",
                                style = MaterialTheme.typography.bodyMedium,
                            )
                        }
                    }
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Text("Tax", style = MaterialTheme.typography.bodyMedium)
                        Text(estimate.totalTax.formatAsMoney(), style = MaterialTheme.typography.bodyMedium)
                    }
                    HorizontalDivider(
                        color = MaterialTheme.colorScheme.outline.copy(alpha = 0.4f),
                        thickness = 1.dp,
                    )
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Text(
                            "Total",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.Bold,
                        )
                        Text(
                            estimate.total.formatAsMoney(),
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.primary,
                        )
                    }
                }
            }
        }

        // Valid until
        if (!estimate.validUntil.isNullOrBlank()) {
            item {
                BrandCard(modifier = Modifier.fillMaxWidth()) {
                    Column(
                        modifier = Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        Text(
                            "Valid Until",
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Text(estimate.validUntil.take(10), style = MaterialTheme.typography.bodyLarge)
                    }
                }
            }
        }

        // Notes
        if (!estimate.notes.isNullOrBlank()) {
            item {
                BrandCard(modifier = Modifier.fillMaxWidth()) {
                    Column(
                        modifier = Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        Text(
                            "Notes",
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Text(estimate.notes, style = MaterialTheme.typography.bodyMedium)
                    }
                }
            }
        }

        // L1330 Send
        item {
            OutlinedButton(
                onClick = onSend,
                modifier = Modifier.fillMaxWidth(),
                enabled = !isActionInProgress,
            ) {
                Icon(Icons.AutoMirrored.Filled.Send, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(8.dp))
                Text("Send")
            }
        }

        // L1331/1332 Approve / Reject
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Button(
                    onClick = onApprove,
                    modifier = Modifier.weight(1f),
                    enabled = !isActionInProgress && !estimate.status.equals("approved", ignoreCase = true),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = MaterialTheme.colorScheme.primary,
                    ),
                ) {
                    Icon(Icons.Default.CheckCircle, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(4.dp))
                    Text("Approve")
                }
                OutlinedButton(
                    onClick = onReject,
                    modifier = Modifier.weight(1f),
                    enabled = !isActionInProgress && !estimate.status.equals("rejected", ignoreCase = true),
                    colors = ButtonDefaults.outlinedButtonColors(
                        contentColor = MaterialTheme.colorScheme.error,
                    ),
                ) {
                    Icon(Icons.Default.ThumbDown, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(4.dp))
                    Text("Reject")
                }
            }
        }

        // L1333 Convert to Ticket CTA — purple primary (positive terminal action)
        item {
            Button(
                onClick = onConvertToTicket,
                modifier = Modifier.fillMaxWidth(),
                enabled = !isActionInProgress && !alreadyConverted,
            ) {
                Icon(Icons.Default.SwapHoriz, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(8.dp))
                Text(if (alreadyConverted) "Already Converted" else "Convert to Ticket")
            }
        }

        // L1334 Convert to Invoice
        item {
            OutlinedButton(
                onClick = onConvertToInvoice,
                modifier = Modifier.fillMaxWidth(),
                enabled = !isActionInProgress,
            ) {
                Icon(Icons.Default.Receipt, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(8.dp))
                Text("Convert to Invoice")
            }
        }
    }
}

// ── L1335 Version dropdown ────────────────────────────────────────────────────

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun VersionDropdown(
    versions: List<EstimateVersion>,
    selectedIndex: Int,
    onVersionSelected: (Int) -> Unit,
) {
    var expanded by rememberSaveable { mutableStateOf(false) }
    val selected = versions.getOrNull(selectedIndex)

    ExposedDropdownMenuBox(
        expanded = expanded,
        onExpandedChange = { expanded = it },
    ) {
        OutlinedTextField(
            value = selected?.let { "v${it.versionNumber} - ${it.createdAt.take(10)}" } ?: "",
            onValueChange = {},
            readOnly = true,
            label = { Text("Version") },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
            modifier = Modifier
                .fillMaxWidth()
                .menuAnchor(MenuAnchorType.PrimaryNotEditable),
        )
        ExposedDropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false },
        ) {
            versions.forEachIndexed { index, version ->
                DropdownMenuItem(
                    text = { Text("v${version.versionNumber} - ${version.createdAt.take(10)} (${version.status})") },
                    onClick = {
                        onVersionSelected(index)
                        expanded = false
                    },
                )
            }
        }
    }
}

// ── L1336 Print / PDF preview ─────────────────────────────────────────────────

/**
 * Opens the system [PrintManager] with an HTML estimate summary.
 *
 * Mirrors [printInvoice] from InvoiceSendActions (wave 15) — reuses the same
 * WebViewPrintDocumentAdapter approach. Falls back gracefully if PrintManager
 * or WebView is unavailable.
 */
fun printEstimate(
    context: Context,
    estimateNumber: String,
    customerName: String?,
    total: Long,
) {
    runCatching {
        val printManager = context.getSystemService(Context.PRINT_SERVICE) as? PrintManager ?: return
        val totalFormatted = "$%.2f".format(total / 100.0)
        val html = buildString {
            append("<html><body>")
            append("<h1>Estimate #$estimateNumber</h1>")
            append("<p>Bizarre Electronics</p>")
            if (!customerName.isNullOrBlank()) append("<p>Customer: $customerName</p>")
            append("<p>Total: $totalFormatted</p>")
            append("</body></html>")
        }
        val adapter = android.webkit.WebView(context).let { wv ->
            wv.loadDataWithBaseURL(null, html, "text/html", "UTF-8", null)
            wv.createPrintDocumentAdapter("Estimate_$estimateNumber")
        }
        printManager.print(
            "Estimate_$estimateNumber",
            adapter,
            PrintAttributes.Builder().build(),
        )
    }
}
