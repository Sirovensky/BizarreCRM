package com.bizarreelectronics.crm.ui.screens.checkin

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CheckInHostScreen(
    customerId: Long,
    deviceId: Long,
    customerName: String,
    deviceName: String,
    onBack: () -> Unit,
    onTicketCreated: (Long) -> Unit,
    viewModel: CheckInViewModel = hiltViewModel(),
) {
    LaunchedEffect(customerId, deviceId) {
        viewModel.init(customerId, deviceId)
    }

    val state by viewModel.uiState.collectAsState()

    Scaffold(
        topBar = {
            CheckInTopBar(
                step = state.currentStep,
                customerName = customerName,
                deviceName = deviceName,
                hasDraft = state.hasDraft,
                onBack = {
                    if (state.currentStep == 0) onBack() else viewModel.goBack()
                },
                onDismissDraft = viewModel::dismissDraftChip,
            )
        },
        bottomBar = {
            CheckInBottomBar(
                step = state.currentStep,
                canAdvance = viewModel.canAdvance(),
                isSubmitting = state.isSubmitting,
                depositCents = state.depositCents,
                onAdvance = {
                    if (state.currentStep < CheckInViewModel.TOTAL_STEPS - 1) {
                        viewModel.advance()
                    } else {
                        viewModel.createTicket(
                            onSuccess = onTicketCreated,
                            onError = { /* snackbar handled by state */ },
                        )
                    }
                },
            )
        },
    ) { paddingValues ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues),
        ) {
            LinearProgressIndicator(
                progress = { state.progressFraction },
                modifier = Modifier
                    .fillMaxWidth()
                    .semantics {
                        contentDescription = "Step ${state.currentStep + 1} of ${CheckInViewModel.TOTAL_STEPS}"
                    },
            )

            AnimatedContent(
                targetState = state.currentStep,
                transitionSpec = {
                    if (targetState > initialState) {
                        (slideInHorizontally { it } + fadeIn()).togetherWith(
                            slideOutHorizontally { -it } + fadeOut()
                        )
                    } else {
                        (slideInHorizontally { -it } + fadeIn()).togetherWith(
                            slideOutHorizontally { it } + fadeOut()
                        )
                    }
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

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CheckInTopBar(
    step: Int,
    customerName: String,
    deviceName: String,
    hasDraft: Boolean,
    onBack: () -> Unit,
    onDismissDraft: () -> Unit,
) {
    val stepTitles = listOf("Symptoms", "Details", "Damage", "Diagnostic", "Quote", "Sign")
    TopAppBar(
        title = {
            Column {
                Text(
                    "Check-in · ${stepTitles.getOrElse(step) { "" }}",
                    style = MaterialTheme.typography.titleMedium,
                )
                Text(
                    "$customerName · $deviceName",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                if (hasDraft) {
                    AssistChip(
                        onClick = onDismissDraft,
                        label = { Text("Draft restored — tap to dismiss") },
                        modifier = Modifier.semantics {
                            contentDescription = "Draft restored. Tap to dismiss notification."
                        },
                    )
                }
            }
        },
        navigationIcon = {
            IconButton(
                onClick = onBack,
                modifier = Modifier.semantics { contentDescription = "Go back" },
            ) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
            }
        },
    )
}

@Composable
private fun CheckInBottomBar(
    step: Int,
    canAdvance: Boolean,
    isSubmitting: Boolean,
    depositCents: Long,
    onAdvance: () -> Unit,
) {
    val isLastStep = step == CheckInViewModel.TOTAL_STEPS - 1
    val ctaLabel = when {
        isSubmitting -> "Creating ticket…"
        isLastStep && depositCents > 0L -> "Create ticket · print label"
        isLastStep -> "Create ticket · print label"
        else -> "Next"
    }

    Button(
        onClick = onAdvance,
        enabled = canAdvance && !isSubmitting,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp)
            .semantics { contentDescription = ctaLabel },
    ) {
        Text(ctaLabel)
    }
}
