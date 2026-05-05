package com.bizarreelectronics.crm.ui.screens.locations

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.LocationCity
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bizarreelectronics.crm.R
import com.bizarreelectronics.crm.data.remote.dto.LocationDto
import com.bizarreelectronics.crm.ui.components.shared.BrandSkeleton
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.ConfirmDialog
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState

/**
 * Location list screen — shows all store locations with active/inactive filter chips.
 *
 * ActionPlan §63.1 (location switcher) and §63.4 (consolidated view for owner role).
 *
 * ConfirmDialog guards "Deactivate location" (destructive) per task constraints.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LocationListScreen(
    onBack: () -> Unit,
    onLocationClick: (Long) -> Unit,
    onCreateLocation: () -> Unit,
    viewModel: LocationListViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val snackbarHostState = remember { SnackbarHostState() }

    // Surface errors via snackbar
    LaunchedEffect(uiState.errorMessage) {
        uiState.errorMessage?.let { msg ->
            snackbarHostState.showSnackbar(msg)
            viewModel.clearError()
        }
    }

    // "Deactivate location" ConfirmDialog
    uiState.pendingDeactivate?.let { loc ->
        ConfirmDialog(
            title = stringResource(R.string.location_deactivate_confirm_title),
            message = stringResource(R.string.location_deactivate_confirm_msg, loc.name),
            confirmLabel = stringResource(R.string.location_deactivate_btn),
            onConfirm = { viewModel.confirmDeactivate() },
            onDismiss = { viewModel.cancelDeactivate() },
            isDestructive = true,
        )
    }

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = stringResource(R.string.locations_title),
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.cd_back),
                        )
                    }
                },
                actions = {
                    IconButton(onClick = onCreateLocation) {
                        Icon(
                            imageVector = Icons.Filled.Add,
                            contentDescription = stringResource(R.string.cd_create_location),
                        )
                    }
                },
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            // Filter chips row
            LazyRow(
                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                item {
                    FilterChip(
                        selected = uiState.filter == LocationFilter.ALL,
                        onClick = { viewModel.setFilter(LocationFilter.ALL) },
                        label = { Text(stringResource(R.string.location_filter_all)) },
                    )
                }
                item {
                    FilterChip(
                        selected = uiState.filter == LocationFilter.ACTIVE,
                        onClick = { viewModel.setFilter(LocationFilter.ACTIVE) },
                        label = { Text(stringResource(R.string.location_filter_active)) },
                    )
                }
                item {
                    FilterChip(
                        selected = uiState.filter == LocationFilter.INACTIVE,
                        onClick = { viewModel.setFilter(LocationFilter.INACTIVE) },
                        label = { Text(stringResource(R.string.location_filter_inactive)) },
                    )
                }
            }

            when {
                uiState.isLoading -> {
                    repeat(4) {
                        BrandSkeleton(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(72.dp)
                                .padding(horizontal = 16.dp, vertical = 4.dp),
                        )
                    }
                }

                uiState.errorMessage != null && uiState.locations.isEmpty() -> {
                    ErrorState(
                        message = uiState.errorMessage ?: stringResource(R.string.location_load_error_title),
                        onRetry = { viewModel.load() },
                    )
                }

                else -> {
                    val filtered = uiState.locations.filter { loc ->
                        when (uiState.filter) {
                            LocationFilter.ALL      -> true
                            LocationFilter.ACTIVE   -> loc.isActive == 1
                            LocationFilter.INACTIVE -> loc.isActive == 0
                        }
                    }
                    if (filtered.isEmpty()) {
                        EmptyState(
                            title = stringResource(R.string.locations_empty_title),
                            subtitle = stringResource(R.string.locations_empty_subtitle),
                        )
                    } else {
                        LazyColumn(
                            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            items(filtered, key = { it.id }) { loc ->
                                LocationListItem(
                                    location = loc,
                                    onClick = { onLocationClick(loc.id) },
                                    onDeactivate = { viewModel.requestDeactivate(loc) },
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun LocationListItem(
    location: LocationDto,
    onClick: () -> Unit,
    onDeactivate: () -> Unit,
) {
    OutlinedCard(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
    ) {
        ListItem(
            headlineContent = {
                Text(
                    text = location.name,
                    style = MaterialTheme.typography.bodyLarge,
                )
            },
            supportingContent = {
                val address = listOfNotNull(location.addressLine, location.city, location.state)
                    .joinToString(", ")
                if (address.isNotEmpty()) {
                    Text(
                        text = address,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            },
            leadingContent = {
                Icon(
                    imageVector = Icons.Filled.LocationCity,
                    contentDescription = stringResource(R.string.cd_location_icon),
                    tint = if (location.isActive == 1)
                        MaterialTheme.colorScheme.primary
                    else
                        MaterialTheme.colorScheme.onSurfaceVariant,
                )
            },
            trailingContent = {
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    if (location.isDefault == 1) {
                        Icon(
                            imageVector = Icons.Filled.Star,
                            contentDescription = stringResource(R.string.cd_location_default),
                            tint = MaterialTheme.colorScheme.primary,
                        )
                    }
                    if (location.isActive == 1) {
                        TextButton(onClick = onDeactivate) {
                            Text(
                                text = stringResource(R.string.location_deactivate_btn),
                                color = MaterialTheme.colorScheme.error,
                            )
                        }
                    }
                }
            },
        )
    }
}
