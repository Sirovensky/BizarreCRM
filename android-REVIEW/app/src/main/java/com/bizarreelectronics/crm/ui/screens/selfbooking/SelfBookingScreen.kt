package com.bizarreelectronics.crm.ui.screens.selfbooking

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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CalendarToday
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.EventBusy
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.R
import com.bizarreelectronics.crm.data.remote.api.BookingConfirmation
import com.bizarreelectronics.crm.data.remote.api.BookingSlot
import com.bizarreelectronics.crm.ui.components.shared.ConfirmDialog

// ---------------------------------------------------------------------------
// §58.1 / §58.2 — Customer-facing appointment self-booking screen
//
// Route: `self-booking/{locationId}`
// Label: R.string.screen_self_booking
//
// No authentication required — uses SelfBookingApi (public endpoints).
// Server endpoints are 404-tolerant; the screen degrades to NotAvailable.
//
// Flow:
//   LoadingSlots → SlotSelection → CustomerInfo → Confirming → Confirmed
//                                                            ↘ Error
//   404 at any step → NotAvailable
// ---------------------------------------------------------------------------

/**
 * Entry-point composable for the customer-facing appointment self-booking screen.
 * Route: `self-booking/{locationId}`
 * Label: [R.string.screen_self_booking]
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SelfBookingScreen(
    onBack: () -> Unit,
    viewModel: SelfBookingViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()

    // ConfirmDialog state for "Cancel booking" during CustomerInfo step.
    var showCancelDialog by remember { mutableStateOf(false) }

    if (showCancelDialog) {
        ConfirmDialog(
            title = stringResource(R.string.self_booking_cancel_dialog_title),
            message = stringResource(R.string.self_booking_cancel_dialog_body),
            confirmLabel = stringResource(R.string.self_booking_cancel_dialog_confirm),
            onConfirm = {
                showCancelDialog = false
                viewModel.onBackToSlots()
            },
            onDismiss = { showCancelDialog = false },
            isDestructive = false,
        )
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = stringResource(R.string.screen_self_booking),
                        style = MaterialTheme.typography.titleMedium,
                    )
                },
                navigationIcon = {
                    IconButton(onClick = {
                        // If on CustomerInfo step, show cancel dialog instead of hard back.
                        if (state is SelfBookingUiState.CustomerInfo) {
                            showCancelDialog = true
                        } else {
                            onBack()
                        }
                    }) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.cd_navigate_back),
                        )
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface,
                    titleContentColor = MaterialTheme.colorScheme.onSurface,
                    navigationIconContentColor = MaterialTheme.colorScheme.onSurfaceVariant,
                ),
            )
        },
    ) { padding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            when (val s = state) {
                is SelfBookingUiState.LoadingSlots -> {
                    CircularProgressIndicator(
                        modifier = Modifier.align(Alignment.Center),
                        color = MaterialTheme.colorScheme.primary,
                    )
                }

                is SelfBookingUiState.SlotSelection -> {
                    SelfBookingSlotContent(
                        state = s,
                        onSlotSelected = viewModel::onSlotSelected,
                        onDateChange = viewModel::onDateChange,
                        onProceed = viewModel::onProceedToCustomerInfo,
                    )
                }

                is SelfBookingUiState.CustomerInfo -> {
                    SelfBookingCustomerInfoContent(
                        state = s,
                        onNameChange = viewModel::onNameChange,
                        onPhoneChange = viewModel::onPhoneChange,
                        onEmailChange = viewModel::onEmailChange,
                        onServiceChange = viewModel::onServiceChange,
                        onNotesChange = viewModel::onNotesChange,
                        onConfirm = viewModel::onConfirmBooking,
                    )
                }

                is SelfBookingUiState.Confirming -> {
                    CircularProgressIndicator(
                        modifier = Modifier.align(Alignment.Center),
                        color = MaterialTheme.colorScheme.primary,
                    )
                }

                is SelfBookingUiState.Confirmed -> {
                    SelfBookingConfirmedContent(
                        confirmation = s.confirmation,
                        onDone = onBack,
                    )
                }

                is SelfBookingUiState.NotAvailable -> {
                    SelfBookingNotAvailable(modifier = Modifier.align(Alignment.Center))
                }

                is SelfBookingUiState.Error -> {
                    SelfBookingError(
                        message = s.message,
                        onRetry = viewModel::retryFromError,
                        modifier = Modifier.align(Alignment.Center),
                    )
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Slot Selection
// ---------------------------------------------------------------------------

@Composable
private fun SelfBookingSlotContent(
    state: SelfBookingUiState.SlotSelection,
    onSlotSelected: (BookingSlot) -> Unit,
    onDateChange: (java.time.LocalDate) -> Unit,
    onProceed: () -> Unit,
) {
    val availableSlots = state.slots.filter { it.available }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            Text(
                text = stringResource(R.string.self_booking_slots_heading),
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.onSurface,
                modifier = Modifier.semantics { heading() },
            )
        }

        if (availableSlots.isEmpty()) {
            item {
                OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(24.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Icon(
                            imageVector = Icons.Default.EventBusy,
                            contentDescription = stringResource(R.string.cd_no_slots_icon),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.size(32.dp),
                        )
                        Text(
                            text = stringResource(R.string.self_booking_no_slots_title),
                            style = MaterialTheme.typography.titleMedium,
                            color = MaterialTheme.colorScheme.onSurface,
                        )
                        Text(
                            text = stringResource(R.string.self_booking_no_slots_subtitle),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        } else {
            items(availableSlots) { slot ->
                SlotItem(
                    slot = slot,
                    selected = slot.slotId == state.selectedSlot?.slotId,
                    onSelect = { onSlotSelected(slot) },
                )
            }
        }

        if (state.selectedSlot != null) {
            item {
                Spacer(Modifier.height(4.dp))
                FilledTonalButton(
                    onClick = onProceed,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text(stringResource(R.string.self_booking_proceed_btn))
                }
            }
        }
    }
}

@Composable
private fun SlotItem(
    slot: BookingSlot,
    selected: Boolean,
    onSelect: () -> Unit,
) {
    OutlinedCard(
        modifier = Modifier.fillMaxWidth(),
        onClick = onSelect,
    ) {
        ListItem(
            headlineContent = {
                Text(
                    text = slot.label ?: slot.startTime,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium,
                )
            },
            supportingContent = slot.service?.let { svc ->
                { Text(text = svc, style = MaterialTheme.typography.bodySmall) }
            },
            leadingContent = {
                Icon(
                    imageVector = Icons.Default.Schedule,
                    contentDescription = stringResource(R.string.cd_slot_time_icon),
                    tint = if (selected) {
                        MaterialTheme.colorScheme.primary
                    } else {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    },
                    modifier = Modifier.size(20.dp),
                )
            },
            trailingContent = if (selected) {
                {
                    FilterChip(
                        selected = true,
                        onClick = {},
                        label = { Text(stringResource(R.string.self_booking_selected_label)) },
                    )
                }
            } else null,
        )
    }
}

// ---------------------------------------------------------------------------
// Customer Info
// ---------------------------------------------------------------------------

@Composable
private fun SelfBookingCustomerInfoContent(
    state: SelfBookingUiState.CustomerInfo,
    onNameChange: (String) -> Unit,
    onPhoneChange: (String) -> Unit,
    onEmailChange: (String) -> Unit,
    onServiceChange: (String) -> Unit,
    onNotesChange: (String) -> Unit,
    onConfirm: () -> Unit,
) {
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                ListItem(
                    headlineContent = {
                        Text(
                            text = state.slot.label ?: state.slot.startTime,
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.SemiBold,
                        )
                    },
                    supportingContent = state.slot.service?.let { svc ->
                        { Text(text = svc, style = MaterialTheme.typography.bodySmall) }
                    },
                    leadingContent = {
                        Icon(
                            imageVector = Icons.Default.CalendarToday,
                            contentDescription = stringResource(R.string.cd_selected_slot_icon),
                            tint = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.size(20.dp),
                        )
                    },
                )
            }
        }

        item {
            Text(
                text = stringResource(R.string.self_booking_your_info_heading),
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.onSurface,
                modifier = Modifier.semantics { heading() },
            )
        }

        item {
            OutlinedTextField(
                value = state.name,
                onValueChange = onNameChange,
                label = { Text(stringResource(R.string.self_booking_field_name)) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
        }

        item {
            OutlinedTextField(
                value = state.phone,
                onValueChange = onPhoneChange,
                label = { Text(stringResource(R.string.self_booking_field_phone)) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone),
                modifier = Modifier.fillMaxWidth(),
            )
        }

        item {
            OutlinedTextField(
                value = state.email,
                onValueChange = onEmailChange,
                label = { Text(stringResource(R.string.self_booking_field_email)) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
                modifier = Modifier.fillMaxWidth(),
            )
        }

        item {
            OutlinedTextField(
                value = state.service,
                onValueChange = onServiceChange,
                label = { Text(stringResource(R.string.self_booking_field_service)) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
        }

        item {
            OutlinedTextField(
                value = state.notes,
                onValueChange = onNotesChange,
                label = { Text(stringResource(R.string.self_booking_field_notes)) },
                minLines = 2,
                maxLines = 4,
                modifier = Modifier.fillMaxWidth(),
            )
        }

        item {
            val canConfirm = state.name.isNotBlank() && state.phone.isNotBlank()
            Spacer(Modifier.height(4.dp))
            FilledTonalButton(
                onClick = onConfirm,
                enabled = canConfirm,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(stringResource(R.string.self_booking_confirm_btn))
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Confirmed
// ---------------------------------------------------------------------------

@Composable
private fun SelfBookingConfirmedContent(
    confirmation: BookingConfirmation,
    onDone: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Icon(
            imageVector = Icons.Default.CheckCircle,
            contentDescription = stringResource(R.string.cd_booking_confirmed_icon),
            tint = MaterialTheme.colorScheme.primary,
            modifier = Modifier.size(56.dp),
        )
        Spacer(Modifier.height(16.dp))
        Text(
            text = stringResource(R.string.self_booking_confirmed_title),
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.onSurface,
            modifier = Modifier.semantics { heading() },
        )
        Spacer(Modifier.height(8.dp))
        val timeLabel = confirmation.startTime
        Text(
            text = stringResource(R.string.self_booking_confirmed_time, timeLabel),
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        confirmation.confirmationCode?.let { code ->
            Spacer(Modifier.height(8.dp))
            OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(16.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Text(
                        text = stringResource(R.string.self_booking_confirmation_code_label),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(Modifier.height(4.dp))
                    Text(
                        text = code,
                        style = MaterialTheme.typography.headlineMedium,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.primary,
                    )
                }
            }
        }
        confirmation.message?.let { msg ->
            Spacer(Modifier.height(8.dp))
            Text(
                text = msg,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Spacer(Modifier.height(24.dp))
        FilledTonalButton(
            onClick = onDone,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text(stringResource(R.string.self_booking_done_btn))
        }
    }
}

// ---------------------------------------------------------------------------
// Not available / error states
// ---------------------------------------------------------------------------

@Composable
private fun SelfBookingNotAvailable(modifier: Modifier = Modifier) {
    Column(
        modifier = modifier.padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(
            imageVector = Icons.Default.EventBusy,
            contentDescription = stringResource(R.string.cd_booking_unavailable_icon),
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(48.dp),
        )
        Text(
            text = stringResource(R.string.self_booking_unavailable_title),
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.onSurface,
        )
        Text(
            text = stringResource(R.string.self_booking_unavailable_subtitle),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun SelfBookingError(
    message: String,
    onRetry: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier.padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(
            imageVector = Icons.Default.Error,
            contentDescription = stringResource(R.string.cd_error_icon),
            tint = MaterialTheme.colorScheme.error,
            modifier = Modifier.size(48.dp),
        )
        Text(
            text = message,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        FilledTonalButton(onClick = onRetry) {
            Text(stringResource(R.string.action_retry))
        }
    }
}
