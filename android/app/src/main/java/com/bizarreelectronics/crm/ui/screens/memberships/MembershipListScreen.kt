package com.bizarreelectronics.crm.ui.screens.memberships

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.data.remote.api.Membership
import com.bizarreelectronics.crm.data.remote.api.MembershipTier
import com.bizarreelectronics.crm.ui.components.shared.BrandCard
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.util.formatAsMoney

// ─── Screen ──────────────────────────────────────────────────────────────────

/**
 * Membership list — active members, tier summary chips, and enroll CTA.
 *
 * Shows "Not available on this server" when the server returns 404.
 * Plan §38.1 / §38.2 L3001-L3011.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MembershipListScreen(
    onBack: () -> Unit,
    onNavigateToCustomer: (Long) -> Unit = {},
    viewModel: MembershipViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsState()
    val enrollState by viewModel.enrollState.collectAsState()
    var showEnrollDialog by remember { mutableStateOf(false) }
    val snackbarHostState = remember { SnackbarHostState() }

    // Surface enroll result via snackbar
    LaunchedEffect(enrollState) {
        when (val s = enrollState) {
            is EnrollState.Success -> {
                snackbarHostState.showSnackbar("Member enrolled (${s.membership.tierName})")
                viewModel.clearEnrollState()
                showEnrollDialog = false
            }
            is EnrollState.Error -> {
                snackbarHostState.showSnackbar(s.message)
                viewModel.clearEnrollState()
            }
            else -> Unit
        }
    }

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Memberships",
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
        floatingActionButton = {
            if (uiState is MembershipUiState.Ready) {
                ExtendedFloatingActionButton(
                    onClick = { showEnrollDialog = true },
                    icon = { Icon(Icons.Default.PersonAdd, contentDescription = null) },
                    text = { Text("Enroll member") },
                )
            }
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        when (val state = uiState) {
            is MembershipUiState.Loading -> {
                Box(
                    modifier = Modifier.fillMaxSize().padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator()
                }
            }

            is MembershipUiState.NotAvailable -> {
                NotAvailableCard(modifier = Modifier.padding(padding).padding(16.dp))
            }

            is MembershipUiState.Error -> {
                ErrorState(
                    message = state.message,
                    onRetry = { viewModel.load() },
                    modifier = Modifier.padding(padding),
                )
            }

            is MembershipUiState.Ready -> {
                MembershipContent(
                    tiers = state.tiers,
                    memberships = state.memberships,
                    onNavigateToCustomer = onNavigateToCustomer,
                    modifier = Modifier.padding(padding),
                )
            }
        }
    }

    // Enroll dialog
    if (showEnrollDialog) {
        val tiers = (uiState as? MembershipUiState.Ready)?.tiers ?: emptyList()
        EnrollMemberDialog(
            tiers = tiers,
            isLoading = enrollState is EnrollState.Loading,
            onDismiss = {
                showEnrollDialog = false
                viewModel.clearEnrollState()
            },
            onConfirm = { customerId, tierId, billing, paymentMethod ->
                viewModel.enroll(customerId, tierId, billing, paymentMethod)
            },
        )
    }
}

// ─── Content ─────────────────────────────────────────────────────────────────

@Composable
private fun MembershipContent(
    tiers: List<MembershipTier>,
    memberships: List<Membership>,
    onNavigateToCustomer: (Long) -> Unit,
    modifier: Modifier = Modifier,
) {
    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // Tier summary chips
        item {
            Text(
                "Tiers",
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.padding(bottom = 8.dp),
            )
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                tiers.forEach { tier ->
                    TierChip(tier = tier)
                }
            }
        }

        // Active members
        item {
            Text(
                "Active members (${memberships.size})",
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.padding(top = 8.dp, bottom = 4.dp),
            )
        }

        if (memberships.isEmpty()) {
            item {
                Text(
                    "No active memberships yet.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        } else {
            items(memberships, key = { it.id }) { membership ->
                MembershipRow(
                    membership = membership,
                    onClick = { onNavigateToCustomer(membership.customerId) },
                )
            }
        }
    }
}

// ─── Tier chip ────────────────────────────────────────────────────────────────

@Composable
fun TierChip(
    tier: MembershipTier,
    modifier: Modifier = Modifier,
) {
    val color = when (tier.name.lowercase()) {
        "gold"   -> MaterialTheme.colorScheme.tertiary
        "silver" -> MaterialTheme.colorScheme.secondary
        else     -> MaterialTheme.colorScheme.surfaceVariant
    }
    SuggestionChip(
        onClick = {},
        label = {
            Text(tier.name, style = MaterialTheme.typography.labelMedium)
        },
        modifier = modifier,
        colors = SuggestionChipDefaults.suggestionChipColors(
            containerColor = color.copy(alpha = 0.15f),
        ),
    )
}

// ─── Membership row ───────────────────────────────────────────────────────────

@Composable
private fun MembershipRow(
    membership: Membership,
    onClick: () -> Unit,
) {
    BrandCard {
        ListItem(
            headlineContent = {
                Text(
                    "Customer #${membership.customerId}",
                    style = MaterialTheme.typography.bodyLarge,
                    fontWeight = FontWeight.Medium,
                )
            },
            supportingContent = {
                Column {
                    Text(
                        "${membership.tierName ?: "—"} · ${membership.status}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    if (membership.expiresAt != null) {
                        Text(
                            "Expires ${membership.expiresAt}",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            },
            trailingContent = {
                Column(horizontalAlignment = Alignment.End) {
                    Text(
                        "${membership.points} pts",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.primary,
                        fontWeight = FontWeight.SemiBold,
                    )
                }
            },
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

// ─── Enroll dialog ────────────────────────────────────────────────────────────

@Composable
private fun EnrollMemberDialog(
    tiers: List<MembershipTier>,
    isLoading: Boolean,
    onDismiss: () -> Unit,
    onConfirm: (customerId: Long, tierId: Long, billing: String, paymentMethod: String) -> Unit,
) {
    var customerIdText by remember { mutableStateOf("") }
    var selectedTier by remember { mutableStateOf(tiers.firstOrNull()) }
    var billing by remember { mutableStateOf("monthly") }
    var paymentMethod by remember { mutableStateOf("cash") }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Enroll member") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedTextField(
                    value = customerIdText,
                    onValueChange = { customerIdText = it },
                    label = { Text("Customer ID") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )

                Text("Tier", style = MaterialTheme.typography.labelMedium)
                tiers.forEach { tier ->
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        RadioButton(
                            selected = selectedTier?.id == tier.id,
                            onClick = { selectedTier = tier },
                        )
                        Column {
                            Text(tier.name, style = MaterialTheme.typography.bodyMedium)
                            Text(
                                "${tier.monthlyPriceCents.formatAsMoney()}/mo · ${tier.discountPercent.toInt()}% off",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }

                Text("Billing", style = MaterialTheme.typography.labelMedium)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilterChip(
                        selected = billing == "monthly",
                        onClick = { billing = "monthly" },
                        label = { Text("Monthly") },
                    )
                    FilterChip(
                        selected = billing == "annual",
                        onClick = { billing = "annual" },
                        label = { Text("Annual") },
                    )
                }

                Text("Payment", style = MaterialTheme.typography.labelMedium)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf("cash", "card").forEach { method ->
                        FilterChip(
                            selected = paymentMethod == method,
                            onClick = { paymentMethod = method },
                            label = { Text(method.replaceFirstChar { it.uppercase() }) },
                        )
                    }
                }
            }
        },
        confirmButton = {
            Button(
                onClick = {
                    val cid = customerIdText.toLongOrNull() ?: return@Button
                    val tid = selectedTier?.id ?: return@Button
                    onConfirm(cid, tid, billing, paymentMethod)
                },
                enabled = !isLoading && customerIdText.isNotBlank() && selectedTier != null,
            ) {
                if (isLoading) {
                    CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                } else {
                    Text("Enroll")
                }
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        },
    )
}

// ─── Not-available card ───────────────────────────────────────────────────────

@Composable
private fun NotAvailableCard(modifier: Modifier = Modifier) {
    BrandCard(modifier = modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(24.dp).fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(
                Icons.Default.CardMembership,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(40.dp),
            )
            Text(
                "Memberships not available on this server",
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                "Update your server to enable membership tiers and loyalty points.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
