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
import androidx.compose.material.icons.filled.Language
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.util.LanguageManager
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.StateFlow
import javax.inject.Inject

// ---------------------------------------------------------------------------
// ViewModel
// ---------------------------------------------------------------------------

/**
 * Thin ViewModel that bridges [LanguageManager] into the Compose world.
 * No side-effects beyond delegating to [LanguageManager.setLanguage].
 */
@HiltViewModel
class LanguageViewModel @Inject constructor(
    private val languageManager: LanguageManager,
) : ViewModel() {

    /** All languages offered in the picker. Immutable. */
    val availableLanguages: List<LanguageManager.Language>
        get() = languageManager.availableLanguages

    /** Currently persisted language tag. Drives the radio-button selection. */
    val currentLanguage: StateFlow<String> = languageManager.currentLanguage

    /** Persist and apply [tag]. On API 33+ the OS handles the recreate. */
    fun setLanguage(tag: String) = languageManager.setLanguage(tag)
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
    val context = LocalContext.current

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Language",
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
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onSelect)
            .semantics(mergeDescendants = true) { role = Role.RadioButton }
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
