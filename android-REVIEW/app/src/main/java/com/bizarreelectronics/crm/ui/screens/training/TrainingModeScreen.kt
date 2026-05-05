package com.bizarreelectronics.crm.ui.screens.training

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.R
import com.bizarreelectronics.crm.data.local.prefs.TrainingPreferences
import com.bizarreelectronics.crm.data.training.FakeTrainingDataSource
import com.bizarreelectronics.crm.data.training.InterceptedSend
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

// =============================================================================
// ViewModel
// =============================================================================

/**
 * §53 — ViewModel for [TrainingModeScreen].
 *
 * All writes go directly to [TrainingPreferences] (SharedPreferences) or to
 * the in-memory [FakeTrainingDataSource] — no server calls are made here.
 */
@HiltViewModel
class TrainingModeViewModel @Inject constructor(
    private val trainingPreferences: TrainingPreferences,
    private val fakeDataSource: FakeTrainingDataSource,
) : ViewModel() {

    // §53.1 — master toggle, exposed as a flow so the UI re-renders reactively
    val trainingModeEnabled: StateFlow<Boolean> =
        trainingPreferences.trainingModeEnabledFlow

    // §53.5 — completed checklist steps
    private val _checklistCompletedSteps = MutableStateFlow(
        trainingPreferences.checklistCompletedSteps,
    )
    val checklistCompletedSteps: StateFlow<Set<Int>> = _checklistCompletedSteps.asStateFlow()

    // §53.4 — intercepted-send log (updated after each toggle or reset)
    private val _interceptedLog = MutableStateFlow(
        fakeDataSource.getInterceptedSendLog(),
    )
    val interceptedLog: StateFlow<List<InterceptedSend>> = _interceptedLog.asStateFlow()

    // -------------------------------------------------------------------------

    /** §53.1 — Enable or disable training mode. */
    fun setTrainingModeEnabled(enabled: Boolean) {
        trainingPreferences.trainingModeEnabled = enabled
    }

    /**
     * §53.3 — Reset all training data (seeded demo + intercepted log +
     * checklist completion).
     */
    fun resetTrainingData() {
        viewModelScope.launch {
            fakeDataSource.reset()
            trainingPreferences.resetTrainingData()
            _checklistCompletedSteps.value = emptySet()
            _interceptedLog.value = emptyList()
        }
    }

    /** §53.5 — Mark a checklist step as complete. */
    fun completeChecklistStep(stepId: Int) {
        trainingPreferences.markChecklistStepCompleted(stepId)
        _checklistCompletedSteps.value = trainingPreferences.checklistCompletedSteps
    }
}

// =============================================================================
// Checklist step definitions (§53.5)
// =============================================================================

/**
 * §53.5 — Onboarding checklist steps shown on [TrainingModeScreen].
 *
 * Each step has a stable integer [id] used for persistence, a human-readable
 * [label], and an optional [navTarget] hint for where to navigate when the
 * user taps the step row.
 */
data class TrainingChecklistStep(
    val id: Int,
    val label: String,
    val description: String,
)

internal val TRAINING_CHECKLIST_STEPS = listOf(
    TrainingChecklistStep(
        id = 1,
        label = "Create a ticket",
        description = "Walk through the check-in flow with a demo customer.",
    ),
    TrainingChecklistStep(
        id = 2,
        label = "Record a payment",
        description = "Process a demo payment via the POS tender screen.",
    ),
    TrainingChecklistStep(
        id = 3,
        label = "Send an SMS",
        description = "Compose and \"send\" a message — it will be intercepted.",
    ),
    TrainingChecklistStep(
        id = 4,
        label = "Search inventory",
        description = "Look up a demo item in the inventory list.",
    ),
    TrainingChecklistStep(
        id = 5,
        label = "View a customer",
        description = "Open a demo customer record and explore the detail screen.",
    ),
)

// =============================================================================
// Screen
// =============================================================================

/**
 * §53 Training Mode settings sub-screen.
 *
 * ## Sections
 * 1. **Master toggle** (§53.1) — enable / disable training mode.
 * 2. **Seeded data info** (§53.2) — explains what demo data is available.
 * 3. **Onboarding checklist** (§53.5) — 5 suggested practice tasks with
 *    per-step completion checkboxes.
 * 4. **Intercepted sends log** (§53.4) — shows SMS / email sends that were
 *    captured instead of being dispatched to the real server.
 * 5. **Reset** (§53.3) — one-tap button to wipe all training state.
 *
 * @param onBack  Navigate back to the Settings screen.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TrainingModeScreen(
    onBack: () -> Unit,
    viewModel: TrainingModeViewModel = hiltViewModel(),
) {
    val trainingEnabled by viewModel.trainingModeEnabled.collectAsState()
    val completedSteps by viewModel.checklistCompletedSteps.collectAsState()
    val interceptedLog by viewModel.interceptedLog.collectAsState()
    var showResetConfirm by remember { mutableStateOf(false) }

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = stringResource(R.string.screen_training_mode),
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.cd_back),
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
            // §53.1 — Master toggle
            // ----------------------------------------------------------------

            OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Icon(
                            Icons.Default.Science,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.tertiary,
                            modifier = Modifier.size(20.dp),
                        )
                        Text(
                            text = stringResource(R.string.training_toggle_title),
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.SemiBold,
                        )
                    }
                    Text(
                        text = stringResource(R.string.training_toggle_description),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            text = stringResource(R.string.training_toggle_label),
                            style = MaterialTheme.typography.bodyMedium,
                            modifier = Modifier.weight(1f),
                        )
                        Switch(
                            checked = trainingEnabled,
                            onCheckedChange = { viewModel.setTrainingModeEnabled(it) },
                            modifier = Modifier.semantics {
                                contentDescription =
                                    "Training mode"
                                stateDescription = if (trainingEnabled) "on" else "off"
                            },
                        )
                    }
                }
            }

            // ----------------------------------------------------------------
            // §53.2 — Seeded data info
            // ----------------------------------------------------------------

            OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Icon(
                            Icons.Default.Storage,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.size(20.dp),
                        )
                        Text(
                            text = stringResource(R.string.training_seeded_data_title),
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.SemiBold,
                        )
                    }
                    Text(
                        text = stringResource(R.string.training_seeded_data_description),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    // Test BlockChyp card hint
                    SeedInfoRow(
                        icon = Icons.Default.CreditCard,
                        iconCd = stringResource(R.string.training_blockchyp_icon_cd),
                        text = stringResource(R.string.training_blockchyp_hint),
                    )
                    SeedInfoRow(
                        icon = Icons.Default.People,
                        iconCd = stringResource(R.string.training_customers_icon_cd),
                        text = stringResource(R.string.training_customers_hint),
                    )
                    SeedInfoRow(
                        icon = Icons.Default.ConfirmationNumber,
                        iconCd = stringResource(R.string.training_tickets_icon_cd),
                        text = stringResource(R.string.training_tickets_hint),
                    )
                }
            }

            // ----------------------------------------------------------------
            // §53.5 — Onboarding checklist
            // ----------------------------------------------------------------

            OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Icon(
                            Icons.Default.Checklist,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.size(20.dp),
                        )
                        Text(
                            text = stringResource(R.string.training_checklist_title),
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.SemiBold,
                        )
                    }
                    Spacer(Modifier.height(4.dp))
                    TRAINING_CHECKLIST_STEPS.forEach { step ->
                        val completed = step.id in completedSteps
                        ChecklistStepRow(
                            step = step,
                            completed = completed,
                            onToggle = {
                                if (!completed) viewModel.completeChecklistStep(step.id)
                            },
                        )
                    }
                }
            }

            // ----------------------------------------------------------------
            // §53.4 — Intercepted sends log
            // ----------------------------------------------------------------

            OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Icon(
                            Icons.Default.Block,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.size(20.dp),
                        )
                        Text(
                            text = stringResource(R.string.training_intercepted_title),
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.SemiBold,
                        )
                    }
                    if (interceptedLog.isEmpty()) {
                        Text(
                            text = stringResource(R.string.training_intercepted_empty),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    } else {
                        interceptedLog.take(5).forEach { send ->
                            InterceptedSendRow(send = send)
                        }
                        if (interceptedLog.size > 5) {
                            Text(
                                text = "+${interceptedLog.size - 5} more",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
            }

            // ----------------------------------------------------------------
            // §53.3 — Reset training data
            // ----------------------------------------------------------------

            FilledTonalButton(
                onClick = { showResetConfirm = true },
                modifier = Modifier
                    .fillMaxWidth()
                    .semantics {
                        contentDescription = "Reset training data"
                    },
            ) {
                Icon(
                    Icons.Default.Refresh,
                    contentDescription = null,
                    modifier = Modifier.size(18.dp),
                )
                Spacer(Modifier.width(8.dp))
                Text(stringResource(R.string.training_reset_button))
            }
        }
    }

    // Reset confirmation dialog
    if (showResetConfirm) {
        AlertDialog(
            onDismissRequest = { showResetConfirm = false },
            icon = {
                Icon(
                    Icons.Default.Refresh,
                    contentDescription = stringResource(R.string.training_reset_dialog_icon_cd),
                )
            },
            title = { Text(stringResource(R.string.training_reset_dialog_title)) },
            text = { Text(stringResource(R.string.training_reset_dialog_message)) },
            confirmButton = {
                FilledTonalButton(
                    onClick = {
                        viewModel.resetTrainingData()
                        showResetConfirm = false
                    },
                ) {
                    Text(stringResource(R.string.training_reset_dialog_confirm))
                }
            },
            dismissButton = {
                TextButton(onClick = { showResetConfirm = false }) {
                    Text(stringResource(R.string.action_cancel))
                }
            },
        )
    }
}

// =============================================================================
// Private composable helpers
// =============================================================================

@Composable
private fun SeedInfoRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    iconCd: String,
    text: String,
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(
            icon,
            contentDescription = iconCd,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(16.dp),
        )
        Text(
            text = text,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun ChecklistStepRow(
    step: TrainingChecklistStep,
    completed: Boolean,
    onToggle: () -> Unit,
) {
    ListItem(
        headlineContent = {
            Text(
                text = step.label,
                style = MaterialTheme.typography.bodyMedium,
                color = if (completed)
                    MaterialTheme.colorScheme.onSurfaceVariant
                else
                    MaterialTheme.colorScheme.onSurface,
            )
        },
        supportingContent = {
            Text(
                text = step.description,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        },
        trailingContent = {
            Checkbox(
                checked = completed,
                onCheckedChange = { if (it) onToggle() },
                modifier = Modifier.semantics {
                    contentDescription = step.label
                    stateDescription = if (completed) "completed" else "not completed"
                },
            )
        },
        modifier = Modifier.fillMaxWidth(),
    )
}

@Composable
private fun InterceptedSendRow(send: InterceptedSend) {
    val typeIcon = when (send.type) {
        InterceptedSend.Type.SMS   -> Icons.Default.Sms
        InterceptedSend.Type.EMAIL -> Icons.Default.Email
    }
    val typeLabel = when (send.type) {
        InterceptedSend.Type.SMS   -> "SMS"
        InterceptedSend.Type.EMAIL -> "Email"
    }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp),
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(
            typeIcon,
            contentDescription = typeLabel,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(16.dp),
        )
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = send.to,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                text = send.preview,
                style = MaterialTheme.typography.bodySmall,
            )
        }
    }
}
