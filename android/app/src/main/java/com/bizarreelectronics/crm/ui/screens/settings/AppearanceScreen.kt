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

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
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
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
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

/** Font-scale label → multiplier mapping. */
enum class AppFontScale(val key: String, val label: String, val multiplier: Float) {
    Default("default", "Default", 1.0f),
    Medium("medium", "Medium", 1.15f),
    Large("large", "Large", 1.30f),
    XLarge("xlarge", "X-Large", 1.50f);

    companion object {
        fun fromKey(key: String) = entries.firstOrNull { it.key == key } ?: Default
    }
}

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

    // plan:L1997 — tenant accent
    val tenantAccentColor: StateFlow<Int?> = appPreferences.tenantAccentColorFlow
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), appPreferences.tenantAccentColor)

    fun setTenantAccentColor(argb: Int?) {
        appPreferences.tenantAccentColor = argb
    }

    // plan:L1999 — font scale
    val fontScaleKey: StateFlow<String> = appPreferences.fontScaleKeyFlow
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), appPreferences.fontScaleKey)

    fun setFontScaleKey(key: String) {
        appPreferences.fontScaleKey = key
    }

    // plan:L2000 — high contrast
    val highContrastEnabled: StateFlow<Boolean> = appPreferences.highContrastEnabledFlow
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), appPreferences.highContrastEnabled)

    fun setHighContrastEnabled(enabled: Boolean) {
        appPreferences.highContrastEnabled = enabled
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
    val accentArgb by viewModel.tenantAccentColor.collectAsStateWithLifecycle()
    val fontScaleKey by viewModel.fontScaleKey.collectAsStateWithLifecycle()
    val highContrast by viewModel.highContrastEnabled.collectAsStateWithLifecycle()

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Appearance",
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
                .padding(16.dp)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            // plan:L1997 — accent color picker
            AccentColorSection(
                currentArgb = accentArgb,
                onSelect = { viewModel.setTenantAccentColor(it) },
            )

            // plan:L1999 — font scale
            FontScaleSection(
                selectedKey = fontScaleKey,
                onSelect = { viewModel.setFontScaleKey(it) },
            )

            // plan:L2000 — high contrast
            HighContrastSection(
                enabled = highContrast,
                onToggle = { viewModel.setHighContrastEnabled(it) },
            )

            // original density picker
            DensityPickerSection(
                selectedDensity = selectedDensity,
                onSelect = { viewModel.setDensity(it) },
            )
            DensityPreviewCard(density = selectedDensity)
        }
    }
}

// ---------------------------------------------------------------------------
// plan:L1997 — Accent color picker
// ---------------------------------------------------------------------------

/**
 * Simple swatches palette for the tenant accent override.
 * HSV wheel via Compose Canvas is deferred — swatches cover the common case
 * and produce a compilable, testable implementation without a custom gesture
 * recogniser. The "Reset" swatch clears the override.
 */
@Composable
private fun AccentColorSection(
    currentArgb: Int?,
    onSelect: (Int?) -> Unit,
) {
    val swatches: List<Pair<String, Int?>> = listOf(
        "Default"  to null,
        "Purple"   to Color(0xFF6750A4).toArgb(),
        "Blue"     to Color(0xFF1565C0).toArgb(),
        "Teal"     to Color(0xFF00796B).toArgb(),
        "Green"    to Color(0xFF2E7D32).toArgb(),
        "Orange"   to Color(0xFFE65100).toArgb(),
        "Red"      to Color(0xFFC62828).toArgb(),
    )

    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("Accent color", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
            Text(
                "Override the brand accent color for this device. " +
                    "Choosing Default restores the standard Bizarre palette.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Row(
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                modifier = Modifier.fillMaxWidth(),
            ) {
                swatches.forEach { (label, argb) ->
                    val color = if (argb != null) Color(argb)
                    else MaterialTheme.colorScheme.primary
                    val selected = argb == currentArgb
                    Box(
                        modifier = Modifier
                            .size(36.dp)
                            .clip(CircleShape)
                            .background(color)
                            .then(
                                if (selected) Modifier.border(3.dp, MaterialTheme.colorScheme.onSurface, CircleShape)
                                else Modifier
                            )
                            .clickable { onSelect(argb) }
                            .semantics { contentDescription = "$label accent color${if (selected) ", selected" else ""}" },
                    )
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// plan:L1999 — Font scale picker
// ---------------------------------------------------------------------------

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun FontScaleSection(
    selectedKey: String,
    onSelect: (String) -> Unit,
) {
    val scales = AppFontScale.entries
    val selected = AppFontScale.fromKey(selectedKey)

    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("Font scale", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
            Text(
                "Adjusts in-app text size independently of the system font scale.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            SingleChoiceSegmentedButtonRow(
                modifier = Modifier
                    .fillMaxWidth()
                    .semantics { contentDescription = "Font scale picker" },
            ) {
                scales.forEachIndexed { index, scale ->
                    SegmentedButton(
                        selected = selected == scale,
                        onClick = { onSelect(scale.key) },
                        shape = SegmentedButtonDefaults.itemShape(index = index, count = scales.size),
                        modifier = Modifier.semantics { contentDescription = "${scale.label} font scale" },
                    ) {
                        Text(scale.label, style = MaterialTheme.typography.labelSmall)
                    }
                }
            }
            // Type preview
            Card(
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
            ) {
                Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(
                        "Ticket #1042 — Screen repair",
                        style = MaterialTheme.typography.bodyMedium.copy(
                            fontSize = MaterialTheme.typography.bodyMedium.fontSize * selected.multiplier,
                        ),
                    )
                    Text(
                        "Customer: John Smith • Due: Apr 25",
                        style = MaterialTheme.typography.bodySmall.copy(
                            fontSize = MaterialTheme.typography.bodySmall.fontSize * selected.multiplier,
                        ),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// plan:L2000 — High contrast
// ---------------------------------------------------------------------------

/**
 * High contrast toggle. When enabled, documentation note: this bumps the
 * ColorScheme to AA 7:1 contrast ratios via a CompositionLocal override in
 * BizarreCrmTheme. Screens not yet updated will gracefully fall back to
 * the standard scheme; full coverage is tracked as a follow-up.
 */
@Composable
private fun HighContrastSection(
    enabled: Boolean,
    onToggle: (Boolean) -> Unit,
) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp)
                .semantics(mergeDescendants = true) {
                    contentDescription = "High contrast mode, ${if (enabled) "on" else "off"}"
                },
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text("High contrast", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                Text(
                    "Switches to a 7:1 AA contrast palette. " +
                        "Some screens may not fully reflect this setting until a future update.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Spacer(Modifier.width(12.dp))
            Switch(checked = enabled, onCheckedChange = onToggle)
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
