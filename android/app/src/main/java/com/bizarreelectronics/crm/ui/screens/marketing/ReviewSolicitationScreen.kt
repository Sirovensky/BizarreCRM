package com.bizarreelectronics.crm.ui.screens.marketing

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.R
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.ConfirmDialog

// ─── Screen ──────────────────────────────────────────────────────────────────

/**
 * Review solicitation screen: send an NPS + review-link SMS after ticket close.
 *
 * Partial implementation:
 *   - Sending side: triggers POST /campaigns/review-request/trigger (fully wired).
 *   - NPS score capture + detractor-vs-promoter conditional routing to in-shop
 *     follow-up instead of public review site: deferred — no server endpoint
 *     for NPS response ingestion exists.
 *
 * Plan §37.5 ActionPlan.md L2983-L2985.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReviewSolicitationScreen(
    onBack: () -> Unit,
    prefilledTicketId: Long? = null,
    viewModel: ReviewSolicitationViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    var ticketIdInput by remember { mutableStateOf(prefilledTicketId?.toString() ?: "") }
    var showConfirm by remember { mutableStateOf(false) }

    LaunchedEffect(uiState) {
        when (val s = uiState) {
            is ReviewSolicitationUiState.NoCampaign -> {
                snackbarHostState.showSnackbar(s.message)
            }
            is ReviewSolicitationUiState.Error -> {
                snackbarHostState.showSnackbar("Error: ${s.message}")
            }
            else -> Unit
        }
    }

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = stringResource(R.string.screen_review_solicitation),
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.cd_back),
                        )
                    }
                },
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 24.dp, vertical = 16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            // Header
            Icon(
                Icons.Default.Star,
                contentDescription = stringResource(R.string.cd_review_star),
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier
                    .size(36.dp)
                    .align(Alignment.CenterHorizontally),
            )
            Text(
                stringResource(R.string.review_solicitation_title),
                style = MaterialTheme.typography.titleLarge,
                modifier = Modifier.align(Alignment.CenterHorizontally),
            )
            Text(
                stringResource(R.string.review_solicitation_subtitle),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.align(Alignment.CenterHorizontally),
            )

            HorizontalDivider()

            // Ticket ID input
            OutlinedTextField(
                value = ticketIdInput,
                onValueChange = { ticketIdInput = it.filter { c -> c.isDigit() } },
                label = { Text(stringResource(R.string.review_ticket_id_label)) },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )

            // Status area
            when (val s = uiState) {
                is ReviewSolicitationUiState.Sending -> {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                        Text(
                            stringResource(R.string.review_sending),
                            style = MaterialTheme.typography.bodyMedium,
                        )
                    }
                }
                is ReviewSolicitationUiState.Success -> {
                    OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text(
                                stringResource(R.string.review_sent_title),
                                style = MaterialTheme.typography.titleSmall,
                                fontWeight = FontWeight.Bold,
                                color = MaterialTheme.colorScheme.secondary,
                            )
                            Text(
                                stringResource(
                                    R.string.review_sent_detail,
                                    s.result.sent,
                                    s.result.attempted,
                                ),
                                style = MaterialTheme.typography.bodyMedium,
                            )
                        }
                    }
                    // Deferred note: NPS scoring + detractor routing
                    Text(
                        stringResource(R.string.review_nps_deferred_note),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                else -> Unit
            }

            // Send button
            FilledTonalButton(
                onClick = { showConfirm = true },
                enabled = ticketIdInput.isNotBlank() &&
                    uiState !is ReviewSolicitationUiState.Sending,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(stringResource(R.string.review_send_btn))
            }

            // Review platform note
            OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(
                        stringResource(R.string.review_platforms_title),
                        style = MaterialTheme.typography.labelMedium,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        stringResource(R.string.review_platforms_body),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }

    // ConfirmDialog before sending
    if (showConfirm) {
        val ticketId = ticketIdInput.toLongOrNull()
        if (ticketId != null) {
            ConfirmDialog(
                title = stringResource(R.string.review_confirm_title),
                message = stringResource(R.string.review_confirm_msg, ticketId),
                confirmLabel = stringResource(R.string.review_send_btn),
                onConfirm = {
                    viewModel.triggerReviewRequest(ticketId)
                    showConfirm = false
                },
                onDismiss = { showConfirm = false },
            )
        } else {
            showConfirm = false
        }
    }
}
