package com.bizarreelectronics.crm.ui.components.shared

import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SelectableChipColors
import androidx.compose.runtime.Composable

/**
 * Brand-aligned [SelectableChipColors] for [androidx.compose.material3.FilterChip].
 *
 * Material 3 defaults paint a selected FilterChip with `secondaryContainer`,
 * which in this app's color scheme is teal — that visually competes with the
 * cream `primary` brand accent used by the POS-to-Ticket flow's CTAs (Next,
 * Get-signature, Start check-in, All OK). The cashier sees teal "selected"
 * states next to cream "action" buttons and reads them as different action
 * classes.
 *
 * Use this everywhere a FilterChip lives inside the flow chrome:
 *
 *     FilterChip(
 *         selected = …,
 *         onClick = …,
 *         label = { Text("…") },
 *         colors = FilterChipDefaults.brandColors(),
 *     )
 *
 * Selected → cream container + dark on-cream text. Idle → transparent
 * surface with onSurface text (Material default).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FilterChipDefaults.brandColors(): SelectableChipColors = filterChipColors(
    selectedContainerColor = MaterialTheme.colorScheme.primary,
    selectedLabelColor = MaterialTheme.colorScheme.onPrimary,
    selectedLeadingIconColor = MaterialTheme.colorScheme.onPrimary,
    selectedTrailingIconColor = MaterialTheme.colorScheme.onPrimary,
)
