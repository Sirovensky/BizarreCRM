package com.bizarreelectronics.crm.ui.screens.stocktake

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.R
import com.bizarreelectronics.crm.data.remote.dto.StocktakeCountLine

/**
 * §60.5 Committed/audit result screen.
 *
 * Shows a summary of variance lines after the count is committed.
 * Includes an "Approval pending" banner (§60.4) since server-side approval
 * is not yet implemented — the banner is informational only.
 * "Done" pops back to inventory.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StocktakeCommittedScreen(
    lines: List<StocktakeCountLine>,
    approvalPending: Boolean,
    sessionId: String?,
    onDone: () -> Unit,
) {
    val variantLines = lines.filter { it.variance != 0 }
    val unchanged = lines.filter { it.variance == 0 }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.stocktake_committed_title)) },
            )
        },
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            contentPadding = PaddingValues(bottom = 24.dp),
        ) {
            // ── Summary header ────────────────────────────────────────────────
            item {
                OutlinedCard(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(16.dp),
                ) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            Icon(
                                Icons.Default.CheckCircle,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.secondary,
                                modifier = Modifier.size(20.dp),
                            )
                            Text(
                                stringResource(R.string.stocktake_committed_summary,
                                    lines.size, variantLines.size),
                                style = MaterialTheme.typography.bodyMedium,
                            )
                        }
                        if (sessionId != null) {
                            Spacer(Modifier.height(4.dp))
                            Text(
                                "Session: $sessionId",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
            }

            // ── Approval pending banner §60.4 ─────────────────────────────────
            if (approvalPending) {
                item {
                    OutlinedCard(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 4.dp),
                    ) {
                        Row(
                            modifier = Modifier.padding(12.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            Icon(
                                Icons.Default.HourglassEmpty,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.tertiary,
                                modifier = Modifier.size(18.dp),
                            )
                            Text(
                                stringResource(R.string.stocktake_approval_pending),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
            }

            // ── Variance lines ────────────────────────────────────────────────
            if (variantLines.isNotEmpty()) {
                item {
                    Text(
                        stringResource(R.string.stocktake_variances_header),
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                        style = MaterialTheme.typography.titleSmall,
                    )
                }
                items(variantLines, key = { it.itemId }) { line ->
                    val varianceColor = if (line.variance > 0) {
                        MaterialTheme.colorScheme.secondary
                    } else {
                        MaterialTheme.colorScheme.error
                    }
                    ListItem(
                        headlineContent = { Text(line.itemName) },
                        supportingContent = {
                            Text(
                                "System ${line.systemQty} → Counted ${line.countedQty}",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        },
                        trailingContent = {
                            Text(
                                if (line.variance >= 0) "+${line.variance}" else "${line.variance}",
                                style = MaterialTheme.typography.labelMedium,
                                color = varianceColor,
                            )
                        },
                    )
                    HorizontalDivider()
                }
            }

            // ── Unchanged lines ───────────────────────────────────────────────
            if (unchanged.isNotEmpty()) {
                item {
                    Text(
                        stringResource(R.string.stocktake_no_variance_header, unchanged.size),
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                        style = MaterialTheme.typography.titleSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            // ── Done button ───────────────────────────────────────────────────
            item {
                Spacer(Modifier.height(16.dp))
                FilledTonalButton(
                    onClick = onDone,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp)
                        .semantics { contentDescription = "Done, return to inventory" },
                ) {
                    Icon(
                        Icons.Default.Done,
                        contentDescription = null,
                        modifier = Modifier.size(18.dp),
                    )
                    Spacer(Modifier.width(8.dp))
                    Text(stringResource(R.string.stocktake_done))
                }
            }
        }
    }
}
