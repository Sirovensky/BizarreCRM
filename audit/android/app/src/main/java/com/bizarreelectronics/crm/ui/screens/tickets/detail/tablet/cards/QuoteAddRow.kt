package com.bizarreelectronics.crm.ui.screens.tickets.detail.tablet.cards

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.ui.screens.tickets.detail.tablet.data.QuoteSuggestion
import java.text.NumberFormat
import java.util.Locale

/**
 * Tablet ticket-detail Quote add-row (T-C6).
 *
 * Sibling of the QuoteCard. Presents a search field that drives the
 * VM's `quoteSuggest(query)` flow on a 250 ms debounce; tapping a
 * suggestion calls `onPick(suggestion)` which the host wires to
 * `viewModel.addQuoteLine(deviceId, suggestion)`.
 *
 * Three kinds render distinctly:
 *  - **Part** — inventory icon, "in stock: N" meta when known.
 *  - **Svc** — wrench icon, category meta.
 *  - **Misc** — plus icon, "Free-text line" meta + 0$ price hint.
 *
 * When [deviceId] is null the field is disabled (we have no device
 * to attach lines to yet); placeholder text explains.
 *
 * @param suggestions current dropdown contents from the VM flow.
 *   Empty list hides the dropdown (collapses card).
 * @param onQueryChange every keystroke; host forwards to
 *   `viewModel.quoteSuggest(it)`.
 * @param onPick suggestion tap; host forwards to
 *   `viewModel.addQuoteLine(deviceId, it)` and clears the query.
 */
@Composable
internal fun QuoteAddRow(
    deviceId: Long?,
    suggestions: List<QuoteSuggestion>,
    onQueryChange: (String) -> Unit,
    onPick: (QuoteSuggestion) -> Unit,
) {
    var query by remember { mutableStateOf("") }
    val canType = deviceId != null

    // Keep VM in sync; clears when user wipes the field.
    LaunchedEffect(query) { onQueryChange(query) }

    Card(
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(modifier = Modifier.padding(horizontal = 14.dp, vertical = 12.dp)) {
            Text(
                "Add quote line",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(bottom = 6.dp),
            )

            OutlinedTextField(
                value = query,
                onValueChange = { query = it.take(120) },
                modifier = Modifier
                    .fillMaxWidth()
                    .semantics { contentDescription = "Search parts, services, or add misc charge" },
                placeholder = {
                    Text(
                        if (canType) "Add part, service, or misc…"
                        else "Add a device first to attach quote lines",
                        style = MaterialTheme.typography.bodyMedium,
                    )
                },
                leadingIcon = {
                    Icon(
                        Icons.Default.Search,
                        contentDescription = null,
                        modifier = Modifier.size(18.dp),
                    )
                },
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = MaterialTheme.colorScheme.primary,
                ),
                enabled = canType,
                singleLine = true,
            )

            // Dropdown — only when we have suggestions.
            if (suggestions.isNotEmpty() && canType) {
                Spacer(Modifier.height(8.dp))
                Surface(
                    color = MaterialTheme.colorScheme.surfaceVariant,
                    shape = RoundedCornerShape(12.dp),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Column(modifier = Modifier.heightIn(max = 320.dp)) {
                        suggestions.forEachIndexed { idx, sugg ->
                            if (idx > 0) {
                                HorizontalDivider(
                                    color = MaterialTheme.colorScheme.surface,
                                    modifier = Modifier.padding(horizontal = 12.dp),
                                )
                            }
                            SuggestionRow(
                                suggestion = sugg,
                                onClick = {
                                    onPick(sugg)
                                    query = ""
                                },
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun SuggestionRow(suggestion: QuoteSuggestion, onClick: () -> Unit) {
    val (icon, tagLabel, tagColor) = when (suggestion.kind) {
        QuoteSuggestion.Kind.PART -> Triple(
            Icons.Default.Inventory2,
            "Part",
            MaterialTheme.colorScheme.primary,
        )
        QuoteSuggestion.Kind.SVC -> Triple(
            Icons.Default.Build,
            "Svc",
            MaterialTheme.colorScheme.tertiary,
        )
        QuoteSuggestion.Kind.MISC -> Triple(
            Icons.Default.Add,
            "Misc",
            MaterialTheme.colorScheme.secondary,
        )
    }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 10.dp)
            .semantics {
                contentDescription = "Add ${suggestion.kind.name.lowercase()}: ${suggestion.name}"
            },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        // Kind icon.
        Box(
            modifier = Modifier
                .size(28.dp)
                .clip(RoundedCornerShape(8.dp))
                .background(tagColor.copy(alpha = 0.18f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = tagColor,
                modifier = Modifier.size(16.dp),
            )
        }

        Column(modifier = Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                KindTag(label = tagLabel, color = tagColor)
                Spacer(Modifier.width(8.dp))
                Text(
                    suggestion.name,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurface,
                    fontWeight = FontWeight.Medium,
                    maxLines = 1,
                )
            }
            val metaParts = listOfNotNull(
                suggestion.meta?.takeIf { it.isNotBlank() },
                suggestion.inStock?.let { "in stock: $it" },
            )
            if (metaParts.isNotEmpty()) {
                Text(
                    metaParts.joinToString(" · "),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                )
            }
        }

        if (suggestion.priceCents > 0L) {
            Text(
                money(suggestion.priceCents / 100.0),
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurface,
            )
        }
    }
}

@Composable
private fun KindTag(label: String, color: Color) {
    Surface(
        color = color.copy(alpha = 0.18f),
        contentColor = color,
        shape = RoundedCornerShape(6.dp),
        modifier = Modifier.height(18.dp),
    ) {
        Text(
            label,
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.padding(horizontal = 6.dp, vertical = 1.dp),
        )
    }
}

private val currencyFmt: NumberFormat = NumberFormat.getCurrencyInstance(Locale.US)
private fun money(value: Double): String = currencyFmt.format(value)
