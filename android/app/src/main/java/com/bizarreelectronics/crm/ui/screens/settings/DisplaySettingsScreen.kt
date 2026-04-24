package com.bizarreelectronics.crm.ui.screens.settings

/**
 * §3.13 L565–L567 — Display sub-screen under Settings.
 *
 * ## Navigation
 * Settings → "Display" row → [DisplaySettingsScreen].
 *
 * ## What this screen does
 *  1. "Activate queue board" button — full-screen, navigates to [Screen.TvQueueBoard]
 *     ([TvQueueBoardScreen]).  Intended for mounting the device on a TV or
 *     wall-mounted display facing customers so they can see their repair status
 *     without approaching the counter.
 *  2. "Keep screen on in regular app use" toggle — writes to
 *     [AppPreferences.keepScreenOn].  When enabled, [MainActivity] sets
 *     `window.addFlags(FLAG_KEEP_SCREEN_ON)` on resume (future hook; pref is
 *     stored now so the flag is ready when wired).
 */

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.PhoneAndroid
import androidx.compose.material.icons.filled.Tv
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject

// ---------------------------------------------------------------------------
// ViewModel
// ---------------------------------------------------------------------------

/**
 * §3.13 — ViewModel for [DisplaySettingsScreen].
 *
 * Owns the "Keep screen on" toggle backed by [AppPreferences.keepScreenOn].
 * All writes go directly to SharedPreferences — no server round-trip.
 */
@HiltViewModel
class DisplaySettingsViewModel @Inject constructor(
    private val appPreferences: AppPreferences,
) : ViewModel() {

    private val _keepScreenOn = MutableStateFlow(appPreferences.keepScreenOn)
    val keepScreenOn: StateFlow<Boolean> = _keepScreenOn.asStateFlow()

    fun setKeepScreenOn(enabled: Boolean) {
        appPreferences.keepScreenOn = enabled
        _keepScreenOn.value = enabled
    }
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

/**
 * §3.13 L565–L567 — Display settings sub-screen.
 *
 * @param onBack            Navigate back to the Settings screen.
 * @param onActivateBoard   Navigate to the full-screen TV queue board.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DisplaySettingsScreen(
    onBack: () -> Unit,
    onActivateBoard: () -> Unit,
    viewModel: DisplaySettingsViewModel = hiltViewModel(),
) {
    val keepScreenOn by viewModel.keepScreenOn.collectAsState()

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Display",
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
            // --- Queue board section ---
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Icon(
                            Icons.Default.Tv,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.size(20.dp),
                        )
                        Text(
                            text = "Queue board",
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.SemiBold,
                        )
                    }
                    Text(
                        text = "Display a full-screen customer queue on a wall-mounted TV or " +
                            "dedicated tablet.  Customers can see their repair status without " +
                            "approaching the counter.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Button(
                        onClick = onActivateBoard,
                        modifier = Modifier
                            .fillMaxWidth()
                            .semantics { contentDescription = "Activate queue board" },
                    ) {
                        Icon(
                            Icons.Default.Tv,
                            contentDescription = null,
                            modifier = Modifier.size(18.dp),
                        )
                        Spacer(Modifier.width(8.dp))
                        Text("Activate queue board")
                    }
                }
            }

            // --- Keep screen on section ---
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Icon(
                            Icons.Default.PhoneAndroid,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.size(20.dp),
                        )
                        Text(
                            text = "Screen behaviour",
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.SemiBold,
                        )
                    }
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                text = "Keep screen on in regular app use",
                                style = MaterialTheme.typography.bodyMedium,
                            )
                            Text(
                                text = "Prevents the display from sleeping while the app is open",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        Switch(
                            checked = keepScreenOn,
                            onCheckedChange = { viewModel.setKeepScreenOn(it) },
                            modifier = Modifier.semantics {
                                contentDescription =
                                    if (keepScreenOn) "Keep screen on, enabled" else "Keep screen on, disabled"
                            },
                        )
                    }
                }
            }
        }
    }
}
