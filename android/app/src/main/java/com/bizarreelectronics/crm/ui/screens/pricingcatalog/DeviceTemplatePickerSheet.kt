package com.bizarreelectronics.crm.ui.screens.pricingcatalog

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PhoneAndroid
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Snackbar
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.data.remote.api.ApplyTemplateResult
import com.bizarreelectronics.crm.data.remote.api.DeviceTemplateDto
import com.bizarreelectronics.crm.ui.components.shared.EmptyState

/**
 * DeviceTemplatePickerSheet — §44.1
 *
 * Bottom sheet that lets the user search device templates and apply one to a
 * ticket. Fires [onApplied] with the [ApplyTemplateResult] when the server
 * confirms the apply. Errors appear in a [Snackbar] without dismissing the
 * sheet so the user can retry.
 *
 * @param ticketId          Target ticket to apply template to.
 * @param deviceModelHint   Optional pre-filter hint (model name substring).
 * @param onApplied         Called with server result once a template is applied.
 * @param onDismiss         Close the sheet without applying.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DeviceTemplatePickerSheet(
    ticketId: Long,
    deviceModelHint: String? = null,
    onApplied: (ApplyTemplateResult) -> Unit,
    onDismiss: () -> Unit,
    viewModel: DeviceTemplatePickerViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val snackbarHostState = remember { SnackbarHostState() }

    // Pre-filter by device model hint on first load.
    LaunchedEffect(deviceModelHint) {
        if (!deviceModelHint.isNullOrBlank()) {
            viewModel.onSearchChanged(deviceModelHint)
        }
    }

    // Consume apply result.
    LaunchedEffect(state.applyResult) {
        state.applyResult?.let { result ->
            onApplied(result)
            viewModel.clearApplyResult()
        }
    }

    // Show apply errors in snackbar.
    LaunchedEffect(state.applyError) {
        state.applyError?.let { msg ->
            snackbarHostState.showSnackbar(msg)
        }
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        Column(modifier = Modifier.fillMaxWidth()) {
            Text(
                text = "Apply device template",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            )

            OutlinedTextField(
                value = state.searchQuery,
                onValueChange = { viewModel.onSearchChanged(it) },
                placeholder = { Text("Search templates…") },
                leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 4.dp),
                singleLine = true,
            )

            Spacer(modifier = Modifier.height(4.dp))

            when {
                state.isLoading -> {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(200.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        CircularProgressIndicator()
                    }
                }

                state.filteredTemplates.isEmpty() -> {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(160.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        EmptyState(
                            icon = Icons.Default.PhoneAndroid,
                            title = if (state.searchQuery.isNotBlank()) "No matches" else "No templates",
                            subtitle = if (state.searchQuery.isNotBlank())
                                "No templates match \"${state.searchQuery}\""
                            else
                                "Create device templates in Settings > Device Templates.",
                        )
                    }
                }

                else -> {
                    LazyColumn(
                        contentPadding = PaddingValues(
                            start = 16.dp,
                            end = 16.dp,
                            bottom = 80.dp,
                        ),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        items(
                            items = state.filteredTemplates,
                            key = { it.id },
                        ) { template ->
                            TemplatePickerCard(
                                template = template,
                                isApplying = state.applyingId == template.id,
                                onApply = {
                                    viewModel.applyTemplate(
                                        templateId = template.id,
                                        ticketId = ticketId,
                                    )
                                },
                            )
                        }
                    }
                }
            }

            SnackbarHost(hostState = snackbarHostState) { data ->
                Snackbar(
                    snackbarData = data,
                    modifier = Modifier.padding(16.dp),
                )
            }
        }
    }
}

// ─── Private composables ──────────────────────────────────────────────────────

@Composable
private fun TemplatePickerCard(
    template: DeviceTemplateDto,
    isApplying: Boolean,
    onApply: () -> Unit,
) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = template.name,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                )
                template.displaySubtitle?.let { sub ->
                    Text(
                        text = sub,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                if (template.displayRepairs.isNotEmpty()) {
                    Text(
                        text = template.displayRepairs.take(3).joinToString(", "),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                    )
                }
            }

            Spacer(modifier = Modifier.width(8.dp))

            if (isApplying) {
                CircularProgressIndicator(modifier = Modifier.size(24.dp))
            } else {
                Button(
                    onClick = onApply,
                    contentPadding = PaddingValues(horizontal = 12.dp, vertical = 6.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = MaterialTheme.colorScheme.primary,
                    ),
                ) {
                    Text("Apply", style = MaterialTheme.typography.labelMedium)
                }
            }
        }
    }
}
