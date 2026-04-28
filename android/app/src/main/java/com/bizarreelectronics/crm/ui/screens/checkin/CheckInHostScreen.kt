package com.bizarreelectronics.crm.ui.screens.checkin

import android.provider.Settings
import androidx.compose.animation.AnimatedContent
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.LinearWavyProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.ui.theme.stepWizardTransition

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CheckInHostScreen(
    customerId: Long,
    deviceId: Long,
    customerName: String,
    deviceName: String,
    deviceModelId: Long? = null,
    onBack: () -> Unit,
    onTicketCreated: (Long) -> Unit,
    viewModel: CheckInViewModel = hiltViewModel(),
) {
    LaunchedEffect(customerId, deviceId, deviceModelId) {
        viewModel.init(customerId, deviceId, deviceModelId)
    }

    val state by viewModel.uiState.collectAsState()

    // §30.4 / §26.4 — Reduce Motion: read system ANIMATOR_DURATION_SCALE once
    // per composition. When 0 the user has disabled animations in Developer
    // Options / Accessibility; stepWizardTransition collapses to instant swap.
    val context = LocalContext.current
    val reduceMotion = remember(context) {
        Settings.Global.getFloat(
            context.contentResolver,
            Settings.Global.ANIMATOR_DURATION_SCALE,
            1f,
        ) == 0f
    }

    val stepTitles = listOf("Symptoms", "Details", "Damage", "Diagnostic", "Quote", "Sign")
    val isLastStep = state.currentStep == CheckInViewModel.TOTAL_STEPS - 1
    val isQuoteStep = state.currentStep == 4
    val ctaLabel = when {
        state.isSubmitting -> "Creating ticket…"
        isLastStep -> "Create ticket · print label"
        isQuoteStep -> "Get signature & check in →"
        else -> "Next"
    }
    val successGreen = com.bizarreelectronics.crm.ui.theme.LocalExtendedColors.current.success
    val buttonColors = if (isLastStep) {
        ButtonDefaults.buttonColors(
            containerColor = successGreen,
            contentColor = Color(0xFF002817),
        )
    } else {
        ButtonDefaults.buttonColors()
    }
    com.bizarreelectronics.crm.ui.components.shared.PosFlowScaffold(
        title = "Check-in · ${stepTitles.getOrElse(state.currentStep) { "" }}",
        subtitle = "$customerName · $deviceName",
        // Host step 0 (Symptoms) = global step 4 (POS=1, Customer=2, Device=3).
        stepIndex = state.currentStep + 3,
        totalSteps = 8,
        onBack = {
            if (state.currentStep == 0) onBack() else viewModel.goBack()
        },
        bottomBar = {
            Button(
                onClick = {
                    if (state.currentStep < CheckInViewModel.TOTAL_STEPS - 1) {
                        viewModel.advance()
                    } else {
                        viewModel.createTicket(
                            onSuccess = onTicketCreated,
                            onError = { /* snackbar handled by state */ },
                        )
                    }
                },
                enabled = viewModel.canAdvance() && !state.isSubmitting,
                colors = buttonColors,
                modifier = Modifier
                    .fillMaxWidth()
                    .semantics { contentDescription = ctaLabel },
            ) {
                Text(ctaLabel)
            }
        },
    ) { paddingValues ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues),
        ) {
            // §30.4 — stepWizardTransition from Motion.kt: respects Reduce Motion
            // (instant cross-fade) and uses branded spring curves when motion is on.
            AnimatedContent(
                targetState = state.currentStep,
                transitionSpec = {
                    stepWizardTransition(
                        direction = if (targetState > initialState) 1 else -1,
                        reduceMotion = reduceMotion,
                    )
                },
                label = "step_transition",
            ) { step ->
                when (step) {
                    0 -> CheckInStep1Symptoms(
                        selected = state.symptoms,
                        onToggle = viewModel::toggleSymptom,
                    )
                    1 -> CheckInStep2Details(
                        customerNotes = state.customerNotes,
                        internalNotes = state.internalNotes,
                        passcodeFormat = state.passcodeFormat,
                        passcode = state.passcode,
                        photoUris = state.photoUris,
                        onCustomerNotesChange = viewModel::setCustomerNotes,
                        onInternalNotesChange = viewModel::setInternalNotes,
                        onPasscodeFormatChange = viewModel::setPasscodeFormat,
                        onPasscodeChange = viewModel::setPasscode,
                        onAddPhoto = viewModel::addPhoto,
                        onRemovePhoto = viewModel::removePhoto,
                    )
                    2 -> CheckInStep3Damage(
                        markers = state.damageMarkers,
                        activeSide = state.activeDamageSide,
                        condition = state.overallCondition,
                        includes = state.includes,
                        ldiStatus = state.ldiStatus,
                        onAddMarker = viewModel::addDamageMarker,
                        onRemoveMarker = viewModel::removeDamageMarker,
                        onSideChange = viewModel::setDamageTab,
                        onConditionChange = viewModel::setCondition,
                        onToggleAccessory = viewModel::toggleAccessory,
                        onLdiChange = viewModel::setLdiStatus,
                    )
                    3 -> CheckInStep4Diagnostic(
                        diagnostics = state.diagnostics,
                        batteryHealthPercent = state.batteryHealthPercent,
                        batteryCycles = state.batteryCycles,
                        onSetResult = viewModel::setDiagnosticResult,
                        onAllOk = viewModel::setAllOk,
                    )
                    4 -> CheckInStep5Quote(
                        subtotalCents = state.quoteSubtotalCents,
                        taxRateBps = state.taxRateBps,
                        depositCents = state.depositCents,
                        depositFullBalance = state.depositFullBalance,
                        laborMinutes = state.laborMinutes,
                        quoteTotalCents = state.quoteTotalCents,
                        dueOnPickupCents = state.dueOnPickupCents,
                        onDepositChange = viewModel::setDepositCents,
                        onDepositFullBalance = viewModel::setDepositFullBalance,
                        onLaborMinutesChange = viewModel::setLaborMinutes,
                        onLaborTechChange = viewModel::setLaborTechId,
                        onSubtotalChange = viewModel::setQuoteSubtotalCents,
                    )
                    5 -> CheckInStep6Sign(
                        agreedToTerms = state.agreedToTerms,
                        consentBackup = state.consentBackup,
                        authorizedDeposit = state.authorizedDeposit,
                        optInSms = state.optInSms,
                        depositCents = state.depositCents,
                        signatureBase64 = state.signatureBase64,
                        customerName = customerName,
                        onAgreedChange = viewModel::setAgreedToTerms,
                        onConsentChange = viewModel::setConsentBackup,
                        onAuthorizeChange = viewModel::setAuthorizedDeposit,
                        onOptInChange = viewModel::setOptInSms,
                        onSigned = viewModel::setSignature,
                    )
                    else -> Unit
                }
            }
        }
    }
}

// CheckInTopBar + CheckInBottomBar moved to PosFlowScaffold
// (ui/components/shared/PosFlowScaffold.kt) — same chrome contract used by
// CheckInEntryScreen + PosEntryScreen so the cashier's eye doesn't have to
// re-anchor between flow screens.
