package com.bizarreelectronics.crm.ui.screens.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.DevicesOther
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.PhoneAndroid
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.R
import com.bizarreelectronics.crm.data.remote.dto.DeviceModelItem
import com.bizarreelectronics.crm.data.remote.dto.ManufacturerItem
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState

/**
 * DeviceCatalogScreen — §44.3
 *
 * Settings sub-screen: two-level hierarchy of manufacturers → device models.
 *
 * Navigation route: `settings/device-catalog`
 * Strings label: `screen_device_catalog`
 *
 * Layout:
 *  - Search bar at top: queries GET /catalog/devices?q=
 *    - In search mode: flat list of matching device models.
 *    - In browse mode: accordion list of manufacturers; tapping expands to
 *      show that manufacturer's device models via GET /catalog/devices?manufacturer_id=.
 *
 * "Admin can add new device" is deferred — the server does not yet expose a
 * POST /catalog/devices endpoint.
 *
 * @param onBack Navigate back.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DeviceCatalogScreen(
    onBack: () -> Unit,
    viewModel: DeviceCatalogViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = stringResource(R.string.screen_device_catalog),
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.cd_navigate_back),
                        )
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
            // ── Search bar ─────────────────────────────────────────────────
            OutlinedTextField(
                value = state.searchQuery,
                onValueChange = { viewModel.search(it) },
                placeholder = { Text(stringResource(R.string.device_catalog_search_hint)) },
                leadingIcon = {
                    Icon(
                        Icons.Default.Search,
                        contentDescription = stringResource(R.string.cd_search),
                    )
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                singleLine = true,
            )

            when {
                state.isLoading -> {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center,
                    ) {
                        CircularProgressIndicator()
                    }
                }

                state.offline -> {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center,
                    ) {
                        EmptyState(
                            icon = Icons.Default.DevicesOther,
                            title = stringResource(R.string.error_offline),
                            subtitle = stringResource(R.string.device_catalog_offline_subtitle),
                        )
                    }
                }

                state.error != null -> {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center,
                    ) {
                        ErrorState(
                            message = state.error ?: "Failed to load device catalog",
                            onRetry = { viewModel.loadManufacturers() },
                        )
                    }
                }

                // ── Search results mode ────────────────────────────────────
                state.searchResults != null -> {
                    when {
                        state.isSearching -> {
                            Box(
                                modifier = Modifier.fillMaxSize(),
                                contentAlignment = Alignment.Center,
                            ) {
                                CircularProgressIndicator()
                            }
                        }

                        state.searchResults!!.isEmpty() -> {
                            Box(
                                modifier = Modifier.fillMaxSize(),
                                contentAlignment = Alignment.Center,
                            ) {
                                EmptyState(
                                    icon = Icons.Default.PhoneAndroid,
                                    title = stringResource(R.string.device_catalog_no_results_title),
                                    subtitle = stringResource(
                                        R.string.device_catalog_no_results_subtitle,
                                        state.searchQuery,
                                    ),
                                )
                            }
                        }

                        else -> {
                            LazyColumn(
                                modifier = Modifier.fillMaxSize(),
                                contentPadding = PaddingValues(vertical = 4.dp),
                            ) {
                                items(
                                    items = state.searchResults!!,
                                    key = { "search_${it.id}" },
                                ) { model ->
                                    DeviceModelRow(model = model)
                                    HorizontalDivider()
                                }
                            }
                        }
                    }
                }

                // ── Browse mode: manufacturers accordion ───────────────────
                state.manufacturers.isEmpty() -> {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center,
                    ) {
                        EmptyState(
                            icon = Icons.Default.DevicesOther,
                            title = stringResource(R.string.device_catalog_empty_title),
                            subtitle = stringResource(R.string.device_catalog_empty_subtitle),
                        )
                    }
                }

                else -> {
                    LazyColumn(
                        modifier = Modifier.fillMaxSize(),
                        contentPadding = PaddingValues(vertical = 4.dp),
                    ) {
                        state.manufacturers.forEach { manufacturer ->
                            val isExpanded = state.expandedManufacturerId == manufacturer.id

                            item(key = "mfr_${manufacturer.id}") {
                                ManufacturerRow(
                                    manufacturer = manufacturer,
                                    isExpanded = isExpanded,
                                    onClick = { viewModel.toggleManufacturer(manufacturer.id) },
                                )
                                HorizontalDivider()
                            }

                            if (isExpanded) {
                                when {
                                    state.isLoadingModels -> {
                                        item(key = "models_loading") {
                                            Box(
                                                modifier = Modifier
                                                    .fillMaxWidth()
                                                    .padding(16.dp),
                                                contentAlignment = Alignment.Center,
                                            ) {
                                                CircularProgressIndicator()
                                            }
                                        }
                                    }

                                    state.modelsError != null -> {
                                        item(key = "models_error") {
                                            Text(
                                                text = state.modelsError!!,
                                                style = MaterialTheme.typography.bodySmall,
                                                color = MaterialTheme.colorScheme.error,
                                                modifier = Modifier.padding(
                                                    horizontal = 32.dp,
                                                    vertical = 8.dp,
                                                ),
                                            )
                                        }
                                    }

                                    state.expandedModels.isEmpty() -> {
                                        item(key = "models_empty") {
                                            Text(
                                                text = stringResource(R.string.device_catalog_no_models),
                                                style = MaterialTheme.typography.bodySmall,
                                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                                modifier = Modifier.padding(
                                                    horizontal = 32.dp,
                                                    vertical = 8.dp,
                                                ),
                                            )
                                        }
                                    }

                                    else -> {
                                        items(
                                            items = state.expandedModels,
                                            key = { "model_${it.id}" },
                                        ) { model ->
                                            DeviceModelRow(model = model, indented = true)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// ─── Private composables ──────────────────────────────────────────────────────

@Composable
private fun ManufacturerRow(
    manufacturer: ManufacturerItem,
    isExpanded: Boolean,
    onClick: () -> Unit,
) {
    ListItem(
        headlineContent = {
            Text(
                text = manufacturer.name,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.SemiBold,
            )
        },
        supportingContent = if (manufacturer.modelCount > 0) {
            {
                Text(
                    text = stringResource(
                        R.string.device_catalog_model_count,
                        manufacturer.modelCount,
                    ),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        } else null,
        leadingContent = {
            Icon(
                Icons.Default.DevicesOther,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        },
        trailingContent = {
            IconButton(onClick = onClick) {
                Icon(
                    if (isExpanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
                    contentDescription = if (isExpanded)
                        stringResource(R.string.device_catalog_collapse, manufacturer.name)
                    else
                        stringResource(R.string.device_catalog_expand, manufacturer.name),
                )
            }
        },
    )
}

@Composable
private fun DeviceModelRow(
    model: DeviceModelItem,
    indented: Boolean = false,
) {
    ListItem(
        headlineContent = {
            Text(
                text = model.name,
                style = MaterialTheme.typography.bodyMedium,
            )
        },
        supportingContent = {
            val parts = buildList {
                model.category?.let { add(it) }
                model.releaseYear?.let { add(it.toString()) }
                if (model.repairCount > 0) add("${model.repairCount} repairs")
            }
            if (parts.isNotEmpty()) {
                Text(
                    text = parts.joinToString(" · "),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        },
        leadingContent = {
            Icon(
                Icons.Default.PhoneAndroid,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        },
        modifier = if (indented)
            Modifier.padding(start = 24.dp)
        else
            Modifier,
    )
}
