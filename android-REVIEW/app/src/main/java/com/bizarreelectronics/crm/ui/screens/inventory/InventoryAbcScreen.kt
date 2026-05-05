package com.bizarreelectronics.crm.ui.screens.inventory

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.db.entities.InventoryItemEntity
import com.bizarreelectronics.crm.data.repository.InventoryRepository
import com.bizarreelectronics.crm.ui.components.shared.BrandCard
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.theme.LocalExtendedColors
import com.bizarreelectronics.crm.util.formatAsMoney
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import javax.inject.Inject

// ─── Domain model ──────────────────────────────────────────────────────────────

/** ABC classification tier for an inventory item. */
enum class AbcTier {
    /** Top items representing 70% of total inventory value. */
    A,
    /** Mid-range items representing the next 20% (70–90% cumulative). */
    B,
    /** Long-tail items representing the remaining 10%. */
    C;

    /** Human-readable label shown in summary tiles and row badges. */
    val label: String get() = name          // "A", "B", "C"
}

/** Single item in the ranked, tier-classified ABC list. */
data class AbcItem(
    val id: Long,
    val name: String,
    val sku: String?,
    val valueCents: Long,           // retailPriceCents × inStock
    val inStock: Int,
    val tier: AbcTier,
    val cumulativePct: Float,       // 0.0–1.0; how far into total value this item sits
)

/** Aggregate stats per tier shown in the summary row. */
data class AbcTierSummary(
    val tier: AbcTier,
    val itemCount: Int,
    val totalValueCents: Long,
    val pctOfItems: Float,          // fraction of total item count
    val pctOfValue: Float,          // fraction of total inventory value
)

/** All state needed to render the ABC screen. */
data class InventoryAbcUiState(
    val items: List<AbcItem> = emptyList(),
    val tierSummaries: List<AbcTierSummary> = emptyList(),
    val totalValueCents: Long = 0L,
    val isLoading: Boolean = true,
)

// ─── ABC computation ──────────────────────────────────────────────────────────

/**
 * Classifies [entities] into ABC tiers based on descending inventory value
 * (retailPriceCents × inStock).
 *
 * Thresholds follow the classic Pareto-based rule:
 *   - **A** — items that collectively account for the top 70% of total value.
 *   - **B** — items that push cumulative value to 90%.
 *   - **C** — remaining items (90–100%).
 *
 * Items with zero value (no retail price or zero stock) are placed in tier C.
 */
internal fun classifyAbc(entities: List<InventoryItemEntity>): List<AbcItem> {
    if (entities.isEmpty()) return emptyList()

    val totalValue = entities.sumOf { it.retailPriceCents * it.inStock }
    if (totalValue == 0L) {
        // All items have zero value — place everything in tier C.
        return entities.map { e ->
            AbcItem(e.id, e.name, e.sku, 0L, e.inStock, AbcTier.C, 1.0f)
        }
    }

    // Sort descending by inventory value; stable sort preserves original order on ties.
    val sorted = entities.sortedByDescending { it.retailPriceCents * it.inStock }

    var cumulative = 0L
    return sorted.map { e ->
        val value = e.retailPriceCents * e.inStock
        cumulative += value
        val cumulativePct = cumulative.toFloat() / totalValue.toFloat()
        val tier = when {
            cumulativePct <= 0.70f -> AbcTier.A
            cumulativePct <= 0.90f -> AbcTier.B
            else                   -> AbcTier.C
        }
        AbcItem(e.id, e.name, e.sku, value, e.inStock, tier, cumulativePct)
    }
}

/** Aggregates [items] into per-tier summary rows. */
internal fun buildTierSummaries(items: List<AbcItem>): List<AbcTierSummary> {
    if (items.isEmpty()) return emptyList()
    val totalItems = items.size.toFloat()
    val totalValue = items.sumOf { it.valueCents }.toFloat()
    return AbcTier.entries.map { tier ->
        val tierItems = items.filter { it.tier == tier }
        val tierValue = tierItems.sumOf { it.valueCents }
        AbcTierSummary(
            tier = tier,
            itemCount = tierItems.size,
            totalValueCents = tierValue,
            pctOfItems = if (totalItems > 0f) tierItems.size / totalItems else 0f,
            pctOfValue = if (totalValue > 0f) tierValue / totalValue else 0f,
        )
    }
}

// ─── ViewModel ────────────────────────────────────────────────────────────────

/**
 * §6.8 ABC analysis ViewModel.
 *
 * Reads the full inventory from Room via [InventoryRepository.getItems], computes
 * ABC tiers entirely on the device, and exposes [uiState] for the screen.
 * No server call is made — the analysis works fully offline from the Room cache.
 */
@HiltViewModel
class InventoryAbcViewModel @Inject constructor(
    inventoryRepository: InventoryRepository,
) : ViewModel() {

    val uiState = inventoryRepository.getItems()
        .map { entities ->
            val abcItems = classifyAbc(entities)
            InventoryAbcUiState(
                items           = abcItems,
                tierSummaries   = buildTierSummaries(abcItems),
                totalValueCents = abcItems.sumOf { it.valueCents },
                isLoading       = false,
            )
        }
        .stateIn(
            scope         = viewModelScope,
            started       = SharingStarted.WhileSubscribed(5_000),
            initialValue  = InventoryAbcUiState(isLoading = true),
        )
}

// ─── Screen ────────────────────────────────────────────────────────────────────

/**
 * §6.8 Inventory ABC analysis screen.
 *
 * Presents a stacked tier-bar (A / B / C proportional width) at the top,
 * three summary tiles showing item count + value share per tier, and a
 * ranked scrollable item list with per-row tier badges.
 *
 * Pure client-side: all computation happens in [InventoryAbcViewModel] using
 * the Room cache populated by the standard inventory sync.
 */
@Composable
fun InventoryAbcScreen(
    onBack: () -> Unit,
    viewModel: InventoryAbcViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsState()

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "ABC Analysis",
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Back",
                        )
                    }
                },
            )
        },
    ) { padding ->
        if (state.isLoading) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
                contentAlignment = Alignment.Center,
            ) {
                CircularProgressIndicator()
            }
            return@Scaffold
        }

        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            // ── Header ───────────────────────────────────────────────────────
            item {
                Text(
                    text = "Inventory value by tier",
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.semantics { heading() },
                )
            }

            // ── Proportional stacked bar ──────────────────────────────────
            item {
                AbcStackedBar(
                    summaries = state.tierSummaries,
                    modifier = Modifier.fillMaxWidth(),
                )
            }

            // ── Tier summary tiles ────────────────────────────────────────
            item {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    state.tierSummaries.forEach { summary ->
                        AbcTileSummaryCard(
                            summary = summary,
                            modifier = Modifier.weight(1f),
                        )
                    }
                }
            }

            // ── Item list ─────────────────────────────────────────────────
            item {
                HorizontalDivider()
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = "${state.items.size} items ranked by value",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            items(state.items, key = { it.id }) { item ->
                AbcItemRow(item = item)
            }
        }
    }
}

// ─── Sub-composables ──────────────────────────────────────────────────────────

/**
 * Proportional stacked bar showing the width share of each ABC tier.
 * TalkBack reads the A / B / C percentages as a single description.
 */
@Composable
private fun AbcStackedBar(
    summaries: List<AbcTierSummary>,
    modifier: Modifier = Modifier,
) {
    val totalValue = summaries.sumOf { it.totalValueCents }.toFloat()
    if (totalValue == 0f) return

    val a11y = summaries.joinToString(", ") { s ->
        "Tier ${s.tier.label}: ${(s.pctOfValue * 100).toInt()}% of value"
    }

    Row(
        modifier = modifier
            .height(32.dp)
            .semantics { contentDescription = "ABC stacked bar. $a11y" },
    ) {
        summaries.forEach { summary ->
            val fraction = summary.totalValueCents / totalValue
            if (fraction > 0f) {
                Box(
                    modifier = Modifier
                        .weight(fraction)
                        .fillMaxSize()
                        .background(tierColor(summary.tier)),
                    contentAlignment = Alignment.Center,
                ) {
                    if (fraction > 0.05f) {
                        Text(
                            text = summary.tier.label,
                            style = MaterialTheme.typography.labelMedium,
                            fontWeight = FontWeight.Bold,
                            color = Color.White,
                        )
                    }
                }
            }
        }
    }
}

/** Summary tile for one ABC tier — shown as a compact [BrandCard]. */
@Composable
private fun AbcTileSummaryCard(
    summary: AbcTierSummary,
    modifier: Modifier = Modifier,
) {
    val a11y = "Tier ${summary.tier.label}: ${summary.itemCount} items, " +
        "${(summary.pctOfValue * 100).toInt()}% of total value"
    BrandCard(
        modifier = modifier.semantics { contentDescription = a11y },
    ) {
        Column(modifier = Modifier.padding(10.dp)) {
            // Tier badge
            Surface(
                shape = RoundedCornerShape(50),
                color = tierColor(summary.tier),
            ) {
                Text(
                    text = summary.tier.label,
                    style = MaterialTheme.typography.labelSmall,
                    fontWeight = FontWeight.Bold,
                    color = Color.White,
                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp),
                )
            }
            Spacer(Modifier.height(6.dp))
            Text(
                text = "${summary.itemCount} items",
                style = MaterialTheme.typography.bodySmall,
            )
            Text(
                text = summary.totalValueCents.formatAsMoney(),
                style = MaterialTheme.typography.bodySmall,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                text = "${(summary.pctOfValue * 100).toInt()}% of value",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

/** Single row in the ranked item list. */
@Composable
private fun AbcItemRow(
    item: AbcItem,
    modifier: Modifier = Modifier,
) {
    val a11y = "Tier ${item.tier.label}: ${item.name}, value ${item.valueCents.formatAsMoney()}, " +
        "${item.inStock} in stock"
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(vertical = 6.dp)
            .semantics { contentDescription = a11y },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        // Tier badge
        Surface(
            shape = RoundedCornerShape(4.dp),
            color = tierColor(item.tier),
            modifier = Modifier.size(width = 28.dp, height = 20.dp),
        ) {
            Box(contentAlignment = Alignment.Center) {
                Text(
                    text = item.tier.label,
                    style = MaterialTheme.typography.labelSmall,
                    fontWeight = FontWeight.Bold,
                    color = Color.White,
                )
            }
        }

        // Name + SKU
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = item.name,
                style = MaterialTheme.typography.bodyMedium,
                maxLines = 1,
            )
            if (!item.sku.isNullOrBlank()) {
                Text(
                    text = item.sku,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }

        // Value
        Column(horizontalAlignment = Alignment.End) {
            Text(
                text = item.valueCents.formatAsMoney(),
                style = MaterialTheme.typography.bodySmall,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                text = "×${item.inStock}",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
    HorizontalDivider(thickness = 0.5.dp)
}

// ─── Color helpers ────────────────────────────────────────────────────────────

/** Returns a stable, tier-associated color. Uses M3 extended / semantic tokens. */
@Composable
private fun tierColor(tier: AbcTier): Color {
    val ext = LocalExtendedColors.current
    return when (tier) {
        AbcTier.A -> ext.success
        AbcTier.B -> ext.warning
        AbcTier.C -> MaterialTheme.colorScheme.outline
    }
}
