package com.bizarreelectronics.crm.ui.screens.settings

/**
 * Language picker — ActionPlan §27.
 *
 * Presents a radio-button list of [LanguageManager.availableLanguages].
 * On selection:
 *   - API 33+: [LanguageManager.setLanguage] hands off to LocaleManager;
 *     the OS recreates the activity automatically — no manual recreate needed.
 *   - API 26-32: [LanguageManager.setLanguage] persists the tag; we call
 *     [Activity.recreate] explicitly so the Configuration override in
 *     attachBaseContext takes effect.
 *
 * A brief Snackbar ("Language updated") is shown before the recreate on older
 * APIs so the user sees feedback before the screen refreshes.
 */

import android.app.Activity
import android.os.Build
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.AttachMoney
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.util.LanguageManager
import com.bizarreelectronics.crm.util.LocaleFormatInit
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.time.ZoneId
import java.util.Currency
import javax.inject.Inject

// ---------------------------------------------------------------------------
// ViewModel
// ---------------------------------------------------------------------------

/**
 * Thin ViewModel that bridges [LanguageManager] into the Compose world.
 * Also exposes timezone and currency overrides (plan:L2004, plan:L2006).
 */
@HiltViewModel
class LanguageViewModel @Inject constructor(
    private val languageManager: LanguageManager,
    private val appPreferences: AppPreferences,
    private val localeFormatInit: LocaleFormatInit,
) : ViewModel() {

    /** All languages offered in the picker. Immutable. */
    val availableLanguages: List<LanguageManager.Language>
        get() = languageManager.availableLanguages

    /** Currently persisted language tag. Drives the radio-button selection. */
    val currentLanguage: StateFlow<String> = languageManager.currentLanguage

    /** Persist and apply [tag]. On API 33+ the OS handles the recreate. */
    fun setLanguage(tag: String) = languageManager.setLanguage(tag)

    // plan:L2004 — timezone override
    private val _timezoneOverride = MutableStateFlow(appPreferences.timezoneOverride)
    val timezoneOverride: StateFlow<String?> = _timezoneOverride.asStateFlow()

    fun setTimezoneOverride(zoneId: String?) {
        appPreferences.timezoneOverride = zoneId
        _timezoneOverride.value = zoneId
        localeFormatInit.onTimezoneChanged(zoneId) // §27.3: propagate to DateFormatter immediately
    }

    // plan:L2006 — currency override
    private val _currencyOverride = MutableStateFlow(appPreferences.currencyOverride)
    val currencyOverride: StateFlow<String?> = _currencyOverride.asStateFlow()

    fun setCurrencyOverride(code: String?) {
        appPreferences.currencyOverride = code
        _currencyOverride.value = code
        localeFormatInit.onCurrencyChanged(code) // §27.3: propagate to CurrencyFormatter immediately
    }

    /** plan:L2004 — sorted list of all available zone IDs. */
    val availableZoneIds: List<String> by lazy {
        ZoneId.getAvailableZoneIds().sorted()
    }

    /** plan:L2006 — sorted list of ISO 4217 currency codes. */
    val availableCurrencies: List<String> by lazy {
        Currency.getAvailableCurrencies().map { it.currencyCode }.sorted()
    }
}

// ---------------------------------------------------------------------------
// Composable
// ---------------------------------------------------------------------------

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LanguageScreen(
    onBack: () -> Unit,
    viewModel: LanguageViewModel = hiltViewModel(),
) {
    val currentTag by viewModel.currentLanguage.collectAsState()
    val timezoneOverride by viewModel.timezoneOverride.collectAsState()
    val currencyOverride by viewModel.currencyOverride.collectAsState()
    val context = LocalContext.current

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Language & Region",
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
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(vertical = 8.dp),
        ) {
            item {
                // Informational header card explaining locale fallback behaviour.
                Card(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 8.dp),
                ) {
                    Row(
                        modifier = Modifier.padding(16.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        verticalAlignment = Alignment.Top,
                    ) {
                        Icon(
                            Icons.Default.Language,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.size(20.dp),
                        )
                        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text(
                                "Per-app language",
                                style = MaterialTheme.typography.titleSmall,
                            )
                            Text(
                                "Choose the language used by this app. " +
                                "Selecting a language that has no translated strings " +
                                "falls back to English automatically.",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
            }

            items(
                items = viewModel.availableLanguages,
                key = { it.tag },
            ) { language ->
                LanguageRow(
                    language = language,
                    selected = language.tag == currentTag,
                    onSelect = {
                        viewModel.setLanguage(language.tag)
                        // API 33+: LocaleManager triggers the recreate for us.
                        // API 26-32: we must recreate explicitly so the manual
                        // Configuration override in attachBaseContext takes effect.
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                            (context as? Activity)?.recreate()
                        }
                    },
                )
            }

            // plan:L2004 — timezone override
            item {
                TimezonePickerRow(
                    currentZoneId = timezoneOverride,
                    availableZoneIds = viewModel.availableZoneIds,
                    onSelect = { viewModel.setTimezoneOverride(it) },
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                )
            }

            // plan:L2005 — date/time/number locale follows OS (documented invariant)
            item {
                Card(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 4.dp),
                ) {
                    Row(modifier = Modifier.padding(16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Icon(
                            Icons.Default.Schedule,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.size(20.dp),
                        )
                        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text("Date, time & number format", style = MaterialTheme.typography.titleSmall)
                            Text(
                                "Follows the OS locale. Change via device Settings > General > Language & Region.",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
            }

            // plan:L2006 — currency override
            item {
                CurrencyPickerRow(
                    currentCode = currencyOverride,
                    availableCurrencies = viewModel.availableCurrencies,
                    onSelect = { viewModel.setCurrencyOverride(it) },
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                )
            }
        }
    }
}

// ---------------------------------------------------------------------------
// plan:L2004 — Timezone picker row
// ---------------------------------------------------------------------------

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TimezonePickerRow(
    currentZoneId: String?,
    availableZoneIds: List<String>,
    onSelect: (String?) -> Unit,
    modifier: Modifier = Modifier,
) {
    var expanded by remember { mutableStateOf(false) }
    val displayValue = currentZoneId ?: "Device default"

    Card(modifier = modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    Icons.Default.Schedule,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(20.dp),
                )
                Text("Timezone override", style = MaterialTheme.typography.titleSmall)
            }
            Text(
                "Override the timezone used for displaying dates and times in the app. " +
                    "\"Device default\" follows the system timezone.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            ExposedDropdownMenuBox(
                expanded = expanded,
                onExpandedChange = { expanded = it },
            ) {
                OutlinedTextField(
                    value = displayValue,
                    onValueChange = {},
                    readOnly = true,
                    modifier = Modifier
                        .fillMaxWidth()
                        .menuAnchor(MenuAnchorType.PrimaryNotEditable),
                    label = { Text("Timezone") },
                    trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded) },
                )
                ExposedDropdownMenu(
                    expanded = expanded,
                    onDismissRequest = { expanded = false },
                    modifier = Modifier.exposedDropdownSize(),
                ) {
                    // "Device default" option
                    DropdownMenuItem(
                        text = { Text("Device default") },
                        onClick = {
                            onSelect(null)
                            expanded = false
                        },
                        contentPadding = ExposedDropdownMenuDefaults.ItemContentPadding,
                    )
                    HorizontalDivider()
                    availableZoneIds.forEach { zoneId ->
                        DropdownMenuItem(
                            text = { Text(zoneId) },
                            onClick = {
                                onSelect(zoneId)
                                expanded = false
                            },
                            contentPadding = ExposedDropdownMenuDefaults.ItemContentPadding,
                        )
                    }
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// plan:L2006 — Currency picker row
// ---------------------------------------------------------------------------

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CurrencyPickerRow(
    currentCode: String?,
    availableCurrencies: List<String>,
    onSelect: (String?) -> Unit,
    modifier: Modifier = Modifier,
) {
    var expanded by remember { mutableStateOf(false) }
    val displayValue = currentCode ?: "Locale default"

    Card(modifier = modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    Icons.Default.AttachMoney,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(20.dp),
                )
                Text("Currency", style = MaterialTheme.typography.titleSmall)
            }
            Text(
                "Override the currency symbol used when displaying money values. " +
                    "\"Locale default\" uses the currency from the active locale.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            ExposedDropdownMenuBox(
                expanded = expanded,
                onExpandedChange = { expanded = it },
            ) {
                OutlinedTextField(
                    value = displayValue,
                    onValueChange = {},
                    readOnly = true,
                    modifier = Modifier
                        .fillMaxWidth()
                        .menuAnchor(MenuAnchorType.PrimaryNotEditable),
                    label = { Text("Currency") },
                    trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded) },
                )
                ExposedDropdownMenu(
                    expanded = expanded,
                    onDismissRequest = { expanded = false },
                    modifier = Modifier.exposedDropdownSize(),
                ) {
                    DropdownMenuItem(
                        text = { Text("Locale default") },
                        onClick = {
                            onSelect(null)
                            expanded = false
                        },
                        contentPadding = ExposedDropdownMenuDefaults.ItemContentPadding,
                    )
                    HorizontalDivider()
                    availableCurrencies.forEach { code ->
                        DropdownMenuItem(
                            text = { Text(code) },
                            onClick = {
                                onSelect(code)
                                expanded = false
                            },
                            contentPadding = ExposedDropdownMenuDefaults.ItemContentPadding,
                        )
                    }
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Private composable
// ---------------------------------------------------------------------------

@Composable
private fun LanguageRow(
    language: LanguageManager.Language,
    selected: Boolean,
    onSelect: () -> Unit,
) {
    // a11y: mergeDescendants collapses RadioButton + language name into one node;
    //       contentDescription announces selection state so users know the active language.
    val selectionState = if (selected) "selected" else "not selected"
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onSelect)
            .semantics(mergeDescendants = true) {
                role = Role.RadioButton
                contentDescription = "${language.displayName}, $selectionState"
            }
            .padding(horizontal = 24.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        RadioButton(
            selected = selected,
            onClick = onSelect,
        )
        Text(
            text = language.displayName,
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.weight(1f),
        )
    }
}
