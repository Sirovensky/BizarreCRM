package com.bizarreelectronics.crm.ui.screens.kiosk

import android.app.Activity
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.TabletAndroid
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject

/**
 * §57 Kiosk / Lock-Task — settings entry-point.
 *
 * Persists `AppPreferences.kioskModeEnabled` and toggles `Activity.startLockTask()`
 * for tablets pinned to a single-task UI (self check-in, TV board).
 *
 * NOTE: full lock-task requires Android Enterprise device-owner provisioning.
 * Without DPC, lock-task is a soft-lock — a manager-PIN exit is recommended.
 */
@HiltViewModel
class KioskModeViewModel @Inject constructor(
    private val appPreferences: AppPreferences,
) : ViewModel() {
    private val _enabled = MutableStateFlow(appPreferences.kioskModeEnabled)
    val enabled = _enabled.asStateFlow()

    fun setEnabled(value: Boolean) {
        _enabled.value = value
        appPreferences.kioskModeEnabled = value
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun KioskModeScreen(
    onBack: () -> Unit,
    viewModel: KioskModeViewModel = hiltViewModel(),
) {
    val context = LocalContext.current
    val enabled by viewModel.enabled.collectAsState()

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Kiosk mode",
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
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
            Card(
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.errorContainer,
                ),
            ) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(
                        "Soft-lock without DPC",
                        style = MaterialTheme.typography.titleMedium,
                        color = MaterialTheme.colorScheme.onErrorContainer,
                    )
                    Text(
                        "True kiosk lock requires Android Enterprise device-owner provisioning. " +
                            "Without it, customers can exit by pressing back+recents simultaneously. " +
                            "Use a manager-PIN exit dialog for soft-lock scenarios.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onErrorContainer,
                    )
                }
            }

            Surface(
                color = MaterialTheme.colorScheme.surfaceContainer,
                shape = MaterialTheme.shapes.medium,
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Icon(Icons.Default.TabletAndroid, contentDescription = null)
                    Column(modifier = Modifier.weight(1f)) {
                        Text("Lock to single task", style = MaterialTheme.typography.titleMedium)
                        Text(
                            "Pin POS / check-in / TV-board to one screen for self-service",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    Switch(
                        checked = enabled,
                        onCheckedChange = { v ->
                            viewModel.setEnabled(v)
                            val activity = context as? Activity
                            if (v) activity?.startLockTask() else activity?.stopLockTask()
                        },
                    )
                }
            }
        }
    }
}
