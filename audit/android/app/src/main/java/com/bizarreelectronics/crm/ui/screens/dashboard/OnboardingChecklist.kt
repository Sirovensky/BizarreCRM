package com.bizarreelectronics.crm.ui.screens.dashboard

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material3.Card
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.db.dao.CustomerDao
import com.bizarreelectronics.crm.data.local.db.dao.TicketDao
import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
import com.bizarreelectronics.crm.data.local.prefs.PinPreferences
import com.bizarreelectronics.crm.ui.theme.SuccessGreen
import com.bizarreelectronics.crm.util.isNotificationPermissionGranted
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import javax.inject.Inject

/**
 * §3.5 — Getting-started checklist surfaced at the top of the dashboard.
 *
 * Five steps, derived from local state (no extra server round-trip):
 *   1. Add your first customer       — CustomerDao.getCount() > 0
 *   2. Create your first ticket      — TicketDao.getCount() > 0
 *   3. Allow notifications           — POST_NOTIFICATIONS grant on Android 13+
 *   4. Set a PIN                     — PinPreferences.isPinSet
 *   5. Enable biometric unlock       — AppPreferences.biometricEnabled
 *
 * The card auto-hides at 100% completion + can be dismissed manually with a
 * "Hide" button so power users aren't nagged forever. Dismiss state is
 * stored in AppPreferences.onboardingDismissed.
 */
data class OnboardingStep(
    val title: String,
    val done: Boolean,
)

@HiltViewModel
class OnboardingViewModel @Inject constructor(
    customerDao: CustomerDao,
    ticketDao: TicketDao,
    private val pinPreferences: PinPreferences,
    private val appPreferences: AppPreferences,
) : ViewModel() {

    val steps: StateFlow<List<OnboardingStep>> = combine(
        customerDao.getCount(),
        ticketDao.getCount(),
        // PIN + biometric + notifications + dismissed live in SharedPreferences
        // — there's no Flow source. Emit a single tick so combine fires; the
        // composable re-collects when the screen re-composes (cheap; toggles
        // are rare).
        flowOf(Unit),
    ) { customerCount, ticketCount, _ ->
        listOf(
            OnboardingStep("Add your first customer", customerCount > 0),
            OnboardingStep("Create your first ticket", ticketCount > 0),
            OnboardingStep("Set a PIN", pinPreferences.isPinSet),
            OnboardingStep("Enable biometric unlock", appPreferences.biometricEnabled),
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5_000),
        initialValue = emptyList(),
    )

    var dismissed: Boolean
        get() = appPreferences.onboardingDismissed
        set(value) {
            appPreferences.onboardingDismissed = value
        }
}

@Composable
fun OnboardingChecklist(
    viewModel: OnboardingViewModel = hiltViewModel(),
    modifier: Modifier = Modifier,
) {
    val context = androidx.compose.ui.platform.LocalContext.current
    val steps by viewModel.steps.collectAsState()
    var dismissed by remember { mutableStateOf(viewModel.dismissed) }

    // Append the runtime-permission step only on Android 13+ where the
    // permission actually exists. Pre-T devices get an implicit "always
    // granted" so we skip the row entirely.
    val notifGranted = isNotificationPermissionGranted(context)
    val allSteps = remember(steps, notifGranted) {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            steps + OnboardingStep("Allow notifications", notifGranted)
        } else {
            steps
        }
    }
    val total = allSteps.size
    val done = allSteps.count { it.done }
    val progress = if (total == 0) 0f else done.toFloat() / total
    val complete = total > 0 && done == total

    AnimatedVisibility(
        visible = !dismissed && !complete && total > 0,
        enter = fadeIn() + expandVertically(),
        exit = fadeOut() + shrinkVertically(),
        modifier = modifier,
    ) {
        Card(modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
            Column(
                modifier = Modifier.padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            "Get set up",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold,
                        )
                        Text(
                            "$done of $total complete",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    TextButton(onClick = {
                        viewModel.dismissed = true
                        dismissed = true
                    }) { Text("Hide") }
                }
                LinearProgressIndicator(
                    progress = { progress },
                    modifier = Modifier.fillMaxWidth(),
                )
                Spacer(Modifier.height(4.dp))
                allSteps.forEach { ChecklistRow(it) }
            }
        }
    }
}

@Composable
private fun ChecklistRow(step: OnboardingStep) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(
            imageVector = if (step.done) Icons.Default.CheckCircle else Icons.Default.RadioButtonUnchecked,
            contentDescription = if (step.done) "Done" else "Not done yet",
            tint = if (step.done) SuccessGreen else MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(20.dp),
        )
        Text(
            text = step.title,
            style = MaterialTheme.typography.bodyMedium,
            color = if (step.done) MaterialTheme.colorScheme.onSurfaceVariant
                else MaterialTheme.colorScheme.onSurface,
            textDecoration = if (step.done) TextDecoration.LineThrough else TextDecoration.None,
            modifier = Modifier.weight(1f),
        )
    }
}
