package com.bizarreelectronics.crm.ui.screens.settings

/**
 * §3.19 L613–L616 — Dashboard density settings screen.
 *
 * ## Navigation
 * Settings > Theme → bottom of ThemeScreen → density section, OR
 * a dedicated route `settings/appearance` routed from [AppNavGraph].
 *
 * ## What this screen does
 * 1. SegmentedButton row: Comfortable / Cozy / Compact
 * 2. Live preview card showing mock KPI tiles rendered at the selected density.
 * 3. Writes the selection to [AppPreferences.setDashboardDensity].
 *
 * Changes propagate immediately to [DashboardScreen] via
 * [LocalDashboardDensity] provided in [MainActivity].
 */

import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.ConfirmationNumber
import androidx.compose.material.icons.filled.ShoppingCart
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.theme.DashboardDensity
import com.bizarreelectronics.crm.util.WindowMode
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.SharingStarted
import androidx.lifecycle.viewModelScope
import javax.inject.Inject

// ---------------------------------------------------------------------------
// ViewModel
// ---------------------------------------------------------------------------

@HiltViewModel
class AppearanceViewModel @Inject constructor(
    private val appPreferences: AppPreferences,
) : ViewModel() {

    val density: StateFlow<DashboardDensity> =
        appPreferences.dashboardDensityFlow
            .map { it }
            .stateIn(
                scope = viewModelScope,
                started = SharingStarted.WhileSubscribed(5_000),
                initialValue = appPreferences.dashboardDensity,
            )

    fun setDensity(density: DashboardDensity) {
        appPreferences.setDashboardDensity(density)
    }
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

/**
 * §3.19 L613–L616 — Appearance / density settings sub-screen.
 *
 * @param onBack  Navigate back (pop the back stack).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AppearanceScreen(
    onBack: () -> Unit,
    viewModel: AppearanceViewModel = hiltViewModel(),
) {
    val selectedDensity by viewModel.density.collectAsStateWithLifecycle()

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Dashboard Density",
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Back",
                        )
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            DensityPickerSection(
                selectedDensity = selectedDensity,
                onSelect = { viewModel.setDensity(it) },
            )
            DensityPreviewCard(density = selectedDensity)
        }
    }
}

// ---------------------------------------------------------------------------
// Density picker — SegmentedButton row
// ---------------------------------------------------------------------------

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DensityPickerSection(
    selectedDensity: DashboardDensity,
    onSelect: (DashboardDensity) -> Unit,
) {
    val modes = DashboardDensity.entries

    Card(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                text = "Layout density",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                text = "Controls how many KPI tiles fit per row and how much " +
                    "spacing appears between sections. Compact is intended for " +
                    "power users and large screens.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            SingleChoiceSegmentedButtonRow(
                modifier = Modifier
                    .fillMaxWidth()
                    .semantics { contentDescription = "Density picker" },
            ) {
                modes.forEachIndexed { index, density ->
                    SegmentedButton(
                        selected = selectedDensity == density,
                        onClick = { onSelect(density) },
                        shape = SegmentedButtonDefaults.itemShape(
                            index = index,
                            count = modes.size,
                        ),
                        modifier = Modifier.semantics {
                            contentDescription = "${density.name} density"
                        },
                    ) {
                        Text(
                            text = density.name,
                            style = MaterialTheme.typography.labelMedium,
                        )
                    }
                }
            }

            // Descriptor for selected mode
            val description = when (selectedDensity) {
                DashboardDensity.Comfortable ->
                    "Generous spacing. 1 KPI column on phone, 2 on tablet."
                DashboardDensity.Cozy ->
                    "Balanced spacing. 2 KPI columns on phone, 3 on tablet."
                DashboardDensity.Compact ->
                    "Tight spacing. 3 KPI columns on phone, 4 on tablet. Intended for power users."
            }
            Text(
                text = description,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

// ---------------------------------------------------------------------------
// Live preview card
// ---------------------------------------------------------------------------

/**
 * §3.19 L616 — Preview card showing mock KPI tiles at the selected density.
 *
 * Renders on a fixed 375 dp phone-equivalent window so the preview is
 * consistent regardless of the actual device width.
 */
@Composable
private fun DensityPreviewCard(density: DashboardDensity) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                text = "Preview (phone layout)",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
            )

            // Simulate phone column count (always preview as phone for clarity)
            val columnCount = density.columnsForWindowSize(WindowMode.Phone)
            val spacing = density.baseSpacing
            val mockTiles = listOf(
                Triple("Open", "12", MaterialTheme.colorScheme.primary),
                Triple("Revenue", "$342", Color(0xFF4CAF50)),
                Triple("Low Stock", "3", Color(0xFFFF9800)),
                Triple("Pending", "5", MaterialTheme.colorScheme.tertiary),
            ).take(columnCount.coerceAtMost(4))

            // Chunk tiles into rows
            val rows = mockTiles.chunked(columnCount)
            Column(verticalArrangement = Arrangement.spacedBy(spacing)) {
                rows.forEach { rowTiles ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(spacing),
                    ) {
                        rowTiles.forEach { (label, value, tint) ->
                            MockKpiTile(
                                label = label,
                                value = value,
                                tint = tint,
                                typeScale = density.typeScale,
                                modifier = Modifier.weight(1f),
                            )
                        }
                        // Pad incomplete last row
                        repeat(columnCount - rowTiles.size) {
                            Spacer(modifier = Modifier.weight(1f))
                        }
                    }
                }
            }

            Text(
                text = "Spacing: ${density.baseSpacing}  •  Columns (phone): ${density.columnsForWindowSize(WindowMode.Phone)}",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun MockKpiTile(
    label: String,
    value: String,
    tint: Color,
    typeScale: Float,
    modifier: Modifier = Modifier,
) {
    val valueStyle = MaterialTheme.typography.titleMedium.copy(
        fontSize = MaterialTheme.typography.titleMedium.fontSize * typeScale,
        fontWeight = FontWeight.Bold,
        color = tint,
    )
    val labelStyle = MaterialTheme.typography.labelSmall.copy(
        fontSize = MaterialTheme.typography.labelSmall.fontSize * typeScale,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )

    Surface(
        modifier = modifier
            .clip(MaterialTheme.shapes.small)
            .border(
                width = 1.dp,
                color = MaterialTheme.colorScheme.outlineVariant,
                shape = MaterialTheme.shapes.small,
            ),
        tonalElevation = 1.dp,
    ) {
        Column(
            modifier = Modifier.padding(8.dp),
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            Text(text = value, style = valueStyle)
            Text(text = label, style = labelStyle)
        }
    }
}
