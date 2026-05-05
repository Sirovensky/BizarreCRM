package com.bizarreelectronics.crm.ui.screens.kiosk

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Phone
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.R

/**
 * §57.2 Kiosk customer check-in screen.
 *
 * Simplified flow: customer types their phone number → the app finds or creates
 * a record → navigates to the signature screen (§57.3).
 *
 * Auto-returns to start after [KioskViewModel.INACTIVITY_TIMEOUT_MS] of inactivity.
 * A manager-exit affordance (small "Exit kiosk" button) navigates to [onExitRequest]
 * which opens the PIN gate (§57.5) without exposing it on the main path.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun KioskCheckInScreen(
    onCustomerResolved: (customerId: Long, customerName: String) -> Unit,
    onExitRequest: () -> Unit,
    viewModel: KioskViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsState()

    // §57.2 — inactivity: when the timer fires, reset to start (blank phone field)
    LaunchedEffect(state.inactivityExpired) {
        if (state.inactivityExpired) {
            viewModel.resetToStart()
        }
    }

    // Navigate forward once a customer record has been resolved
    LaunchedEffect(state.resolvedCustomerId) {
        val id = state.resolvedCustomerId
        if (id != null) {
            onCustomerResolved(id, state.resolvedCustomerName)
        }
    }

    // Start the inactivity timer when the screen enters composition
    LaunchedEffect(Unit) {
        viewModel.onActivity()
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        stringResource(R.string.kiosk_checkin_title),
                        style = MaterialTheme.typography.titleLarge,
                    )
                },
                actions = {
                    TextButton(
                        onClick = onExitRequest,
                        modifier = Modifier.semantics {
                            contentDescription = "Exit kiosk mode (requires manager PIN)"
                        },
                    ) {
                        Text(
                            stringResource(R.string.kiosk_exit_button),
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                },
            )
        },
    ) { paddingValues ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues),
            contentAlignment = Alignment.Center,
        ) {
            Column(
                modifier = Modifier
                    .widthIn(max = 480.dp)
                    .fillMaxWidth()
                    .padding(horizontal = 24.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(20.dp),
            ) {
                Text(
                    stringResource(R.string.kiosk_checkin_headline),
                    style = MaterialTheme.typography.headlineMedium,
                    textAlign = TextAlign.Center,
                )
                Text(
                    stringResource(R.string.kiosk_checkin_subhead),
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                )

                OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                    Column(
                        modifier = Modifier.padding(20.dp),
                        verticalArrangement = Arrangement.spacedBy(16.dp),
                    ) {
                        OutlinedTextField(
                            value = state.phoneQuery,
                            onValueChange = { viewModel.onPhoneQueryChange(it) },
                            label = { Text(stringResource(R.string.kiosk_phone_label)) },
                            leadingIcon = {
                                Icon(
                                    Icons.Default.Phone,
                                    contentDescription = stringResource(R.string.kiosk_phone_icon_cd),
                                )
                            },
                            keyboardOptions = KeyboardOptions(
                                keyboardType = KeyboardType.Phone,
                                imeAction = ImeAction.Done,
                            ),
                            keyboardActions = KeyboardActions(
                                onDone = { viewModel.lookupCustomer() },
                            ),
                            isError = state.errorMessage != null,
                            supportingText = state.errorMessage?.let { { Text(it) } },
                            singleLine = true,
                            modifier = Modifier
                                .fillMaxWidth()
                                .semantics { contentDescription = "Phone number input" },
                        )

                        if (state.isLoading) {
                            Box(
                                modifier = Modifier.fillMaxWidth(),
                                contentAlignment = Alignment.Center,
                            ) {
                                CircularProgressIndicator(
                                    modifier = Modifier.semantics {
                                        contentDescription = "Looking up customer record"
                                    },
                                )
                            }
                        } else {
                            FilledTonalButton(
                                onClick = { viewModel.lookupCustomer() },
                                enabled = state.phoneQuery.isNotBlank(),
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .semantics { contentDescription = "Look up or create customer record" },
                            ) {
                                Text(stringResource(R.string.kiosk_checkin_cta))
                            }
                        }
                    }
                }

                Spacer(modifier = Modifier.height(8.dp))

                Text(
                    stringResource(R.string.kiosk_inactivity_note),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                )
            }
        }
    }
}
