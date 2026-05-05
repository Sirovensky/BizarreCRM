package com.bizarreelectronics.crm.ui.screens.locations

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.LocationCity
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.StarBorder
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bizarreelectronics.crm.R
import com.bizarreelectronics.crm.ui.components.shared.BrandSkeleton
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.ConfirmDialog
import com.bizarreelectronics.crm.ui.components.shared.ErrorState

/**
 * Location detail screen — shows full config for a single location.
 *
 * ActionPlan §63.2 — per-location config view (hours, staff roster, etc.
 * are deferred per NOTE-defer; address/phone/email/timezone/notes shown here).
 *
 * ConfirmDialog guards "Set as default" and "Deactivate location" actions.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LocationDetailScreen(
    locationId: Long,
    onBack: () -> Unit,
    onEdit: (Long) -> Unit,
    viewModel: LocationDetailViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(locationId) {
        viewModel.load(locationId)
    }

    LaunchedEffect(uiState.errorMessage) {
        uiState.errorMessage?.let { msg ->
            snackbarHostState.showSnackbar(msg)
            viewModel.clearError()
        }
    }

    // "Set as default" ConfirmDialog
    uiState.pendingSetDefault?.let { loc ->
        ConfirmDialog(
            title = stringResource(R.string.location_set_default_confirm_title),
            message = stringResource(R.string.location_set_default_confirm_msg, loc.name),
            confirmLabel = stringResource(R.string.location_set_default_btn),
            onConfirm = { viewModel.confirmSetDefault() },
            onDismiss = { viewModel.cancelSetDefault() },
        )
    }

    // "Deactivate location" ConfirmDialog (destructive)
    uiState.pendingDeactivate?.let { loc ->
        ConfirmDialog(
            title = stringResource(R.string.location_deactivate_confirm_title),
            message = stringResource(R.string.location_deactivate_confirm_msg, loc.name),
            confirmLabel = stringResource(R.string.location_deactivate_btn),
            onConfirm = { viewModel.confirmDeactivate(onSuccess = onBack) },
            onDismiss = { viewModel.cancelDeactivate() },
            isDestructive = true,
        )
    }

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = uiState.location?.name
                    ?: stringResource(R.string.location_detail_title),
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.cd_back),
                        )
                    }
                },
                actions = {
                    uiState.location?.let {
                        IconButton(onClick = { onEdit(locationId) }) {
                            Icon(
                                imageVector = Icons.Filled.Edit,
                                contentDescription = stringResource(R.string.cd_edit_location),
                            )
                        }
                    }
                },
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        when {
            uiState.isLoading -> {
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding)
                        .padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    repeat(5) {
                        BrandSkeleton(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(56.dp),
                        )
                    }
                }
            }

            uiState.errorMessage != null && uiState.location == null -> {
                ErrorState(
                    message = uiState.errorMessage ?: stringResource(R.string.location_load_error_title),
                    onRetry = { viewModel.load(locationId) },
                )
            }

            else -> {
                val loc = uiState.location ?: return@Scaffold
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding)
                        .verticalScroll(rememberScrollState())
                        .padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    // Status badges
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        FilterChip(
                            selected = loc.isActive == 1,
                            onClick = {},
                            label = {
                                Text(
                                    if (loc.isActive == 1)
                                        stringResource(R.string.location_status_active)
                                    else
                                        stringResource(R.string.location_status_inactive)
                                )
                            },
                            leadingIcon = {
                                Icon(
                                    imageVector = Icons.Filled.LocationCity,
                                    contentDescription = null,
                                )
                            },
                        )
                        if (loc.isDefault == 1) {
                            FilterChip(
                                selected = true,
                                onClick = {},
                                label = { Text(stringResource(R.string.location_label_default)) },
                                leadingIcon = {
                                    Icon(
                                        imageVector = Icons.Filled.Star,
                                        contentDescription = stringResource(R.string.cd_location_default),
                                    )
                                },
                            )
                        }
                    }

                    // Info card
                    OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            LocationInfoRow(label = stringResource(R.string.location_field_name), value = loc.name)
                            loc.addressLine?.let { LocationInfoRow(stringResource(R.string.location_field_address), it) }
                            loc.city?.let { LocationInfoRow(stringResource(R.string.location_field_city), it) }
                            loc.state?.let { LocationInfoRow(stringResource(R.string.location_field_state), it) }
                            loc.postcode?.let { LocationInfoRow(stringResource(R.string.location_field_postcode), it) }
                            LocationInfoRow(stringResource(R.string.location_field_country), loc.country)
                            loc.phone?.let { LocationInfoRow(stringResource(R.string.location_field_phone), it) }
                            loc.email?.let { LocationInfoRow(stringResource(R.string.location_field_email), it) }
                            LocationInfoRow(stringResource(R.string.location_field_timezone), loc.timezone)
                            loc.notes?.let { LocationInfoRow(stringResource(R.string.location_field_notes), it) }
                            loc.userCount?.let {
                                LocationInfoRow(
                                    stringResource(R.string.location_field_staff_count),
                                    it.toString(),
                                )
                            }
                        }
                    }

                    // Actions (admin only — server enforces 403 for non-admin)
                    if (loc.isDefault == 0 && loc.isActive == 1) {
                        FilledTonalButton(
                            onClick = { viewModel.requestSetDefault(loc) },
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Icon(
                                imageVector = Icons.Filled.StarBorder,
                                contentDescription = null,
                            )
                            Spacer(Modifier.width(8.dp))
                            Text(stringResource(R.string.location_set_default_btn))
                        }
                    }

                    if (loc.isActive == 1 && loc.isDefault == 0) {
                        OutlinedButton(
                            onClick = { viewModel.requestDeactivate(loc) },
                            modifier = Modifier.fillMaxWidth(),
                            colors = ButtonDefaults.outlinedButtonColors(
                                contentColor = MaterialTheme.colorScheme.error,
                            ),
                        ) {
                            Text(stringResource(R.string.location_deactivate_btn))
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun LocationInfoRow(label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.weight(0.4f),
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.weight(0.6f),
        )
    }
}
