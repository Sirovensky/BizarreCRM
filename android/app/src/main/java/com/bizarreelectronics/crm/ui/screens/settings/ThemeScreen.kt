package com.bizarreelectronics.crm.ui.screens.settings

/**
 * Theme picker — ActionPlan §1.4 line 188 / §19 / §30.
 *
 * Three-option radio list (System default / Light / Dark) + an optional
 * Material You dynamic-color Switch (Android 12+ only). Theme changes apply
 * immediately — AppPreferences exposes StateFlows that MainActivity observes,
 * so BizarreCrmTheme re-renders without an activity recreate.
 *
 * A small preview card shows the active color-scheme surface/primary swatches
 * so the user can see the effect before navigating back.
 */

import android.os.Build
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.DarkMode
import androidx.compose.material.icons.filled.LightMode
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material.icons.filled.SettingsBrightness
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import javax.inject.Inject

// ---------------------------------------------------------------------------
// UI state
// ---------------------------------------------------------------------------

/**
 * Immutable snapshot of the current theme settings consumed by [ThemeScreen].
 *
 * @param mode       One of "system", "light", or "dark".
 * @param dynamicColor  Whether Material You dynamic color is active.
 */
data class ThemeUiState(
    val mode: String = "system",
    val dynamicColor: Boolean = false,
)

// ---------------------------------------------------------------------------
// ViewModel
// ---------------------------------------------------------------------------

@HiltViewModel
class ThemeViewModel @Inject constructor(
    private val appPreferences: AppPreferences,
) : ViewModel() {

    private val _state = MutableStateFlow(
        ThemeUiState(
            mode = appPreferences.darkMode,
            dynamicColor = appPreferences.dynamicColorEnabled,
        ),
    )
    val state: StateFlow<ThemeUiState> = _state.asStateFlow()

    init {
        // Keep the UI state in sync with AppPreferences flows so that if another
        // code path updates the prefs the ThemeScreen reflects the change.
        combine(
            appPreferences.darkModeFlow,
            appPreferences.dynamicColorFlow,
        ) { mode, dynamic ->
            ThemeUiState(mode = mode, dynamicColor = dynamic)
        }
            .onEach { _state.value = it }
            .launchIn(viewModelScope)
    }

    /** Persist the selected mode ("system" | "light" | "dark") and update the theme immediately. */
    fun setMode(mode: String) {
        appPreferences.darkMode = mode
        // _state is updated reactively via the combine above.
    }

    /** Persist the dynamic-color flag and update the theme immediately. */
    fun setDynamicColor(enabled: Boolean) {
        appPreferences.dynamicColorEnabled = enabled
        // _state is updated reactively via the combine above.
    }
}

// ---------------------------------------------------------------------------
// Composable
// ---------------------------------------------------------------------------

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ThemeScreen(
    onBack: () -> Unit,
    viewModel: ThemeViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsStateWithLifecycle()

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Theme",
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
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            // ----------------------------------------------------------------
            // Appearance section
            // ----------------------------------------------------------------
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Text(
                        text = "Appearance",
                        style = MaterialTheme.typography.titleSmall,
                    )

                    Spacer(Modifier.height(4.dp))

                    ThemeRadioRow(
                        icon = Icons.Default.SettingsBrightness,
                        label = "System default",
                        description = "Follows your device light/dark setting",
                        selected = state.mode == "system",
                        onSelect = { viewModel.setMode("system") },
                    )

                    HorizontalDivider(
                        color = MaterialTheme.colorScheme.outline.copy(alpha = 0.4f),
                        thickness = 1.dp,
                    )

                    ThemeRadioRow(
                        icon = Icons.Default.LightMode,
                        label = "Light",
                        description = "Always use the light theme",
                        selected = state.mode == "light",
                        onSelect = { viewModel.setMode("light") },
                    )

                    HorizontalDivider(
                        color = MaterialTheme.colorScheme.outline.copy(alpha = 0.4f),
                        thickness = 1.dp,
                    )

                    ThemeRadioRow(
                        icon = Icons.Default.DarkMode,
                        label = "Dark",
                        description = "Always use the dark theme",
                        selected = state.mode == "dark",
                        onSelect = { viewModel.setMode("dark") },
                    )
                }
            }

            // ----------------------------------------------------------------
            // Dynamic color (Android 12+ only)
            // ----------------------------------------------------------------
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                Card(modifier = Modifier.fillMaxWidth()) {
                    Column(
                        modifier = Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Text(
                            text = "Color",
                            style = MaterialTheme.typography.titleSmall,
                        )
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Icon(
                                Icons.Default.Palette,
                                contentDescription = "Dynamic color",
                                modifier = Modifier.size(20.dp),
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            Spacer(Modifier.width(12.dp))
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    "Dynamic color (Material You)",
                                    style = MaterialTheme.typography.bodyMedium,
                                )
                                Text(
                                    "Derive the color scheme from your wallpaper",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                            Switch(
                                checked = state.dynamicColor,
                                onCheckedChange = { viewModel.setDynamicColor(it) },
                            )
                        }
                    }
                }
            }

            // ----------------------------------------------------------------
            // Preview card
            // ----------------------------------------------------------------
            ThemePreviewCard(state = state)
        }
    }
}

// ---------------------------------------------------------------------------
// Private composables
// ---------------------------------------------------------------------------

@Composable
private fun ThemeRadioRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    description: String,
    selected: Boolean,
    onSelect: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onSelect)
            .semantics(mergeDescendants = true) { role = Role.RadioButton }
            .padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(
            icon,
            contentDescription = null,
            modifier = Modifier.size(20.dp),
            tint = if (selected) MaterialTheme.colorScheme.primary
            else MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = label,
                style = MaterialTheme.typography.bodyMedium,
            )
            Text(
                text = description,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        RadioButton(
            selected = selected,
            onClick = onSelect,
        )
    }
}

/**
 * Small preview strip showing the active surface / primary / background
 * swatches so the user can see the current color-scheme at a glance.
 */
@Composable
private fun ThemePreviewCard(state: ThemeUiState) {
    val modeLabel = when (state.mode) {
        "dark"  -> "Dark"
        "light" -> "Light"
        else    -> "System default"
    }
    val dynamicLabel = if (
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && state.dynamicColor
    ) " · Dynamic color on" else ""

    Card(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                text = "Preview",
                style = MaterialTheme.typography.titleSmall,
            )
            Text(
                text = "$modeLabel$dynamicLabel",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            // Swatch row: background · surface · primary · secondary
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                ColorSwatch(
                    color = MaterialTheme.colorScheme.background,
                    label = "BG",
                )
                ColorSwatch(
                    color = MaterialTheme.colorScheme.surface,
                    label = "Surface",
                )
                ColorSwatch(
                    color = MaterialTheme.colorScheme.primary,
                    label = "Primary",
                )
                ColorSwatch(
                    color = MaterialTheme.colorScheme.secondary,
                    label = "Secondary",
                )
            }
        }
    }
}

@Composable
private fun ColorSwatch(
    color: androidx.compose.ui.graphics.Color,
    label: String,
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Box(
            modifier = Modifier
                .size(40.dp)
                .clip(RoundedCornerShape(8.dp))
                .background(color),
        )
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
