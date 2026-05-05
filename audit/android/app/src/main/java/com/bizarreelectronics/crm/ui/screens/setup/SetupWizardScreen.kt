package com.bizarreelectronics.crm.ui.screens.setup

import android.provider.Settings
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.ui.components.PredictiveBackScaffold
import com.bizarreelectronics.crm.ui.components.shared.ConfirmDialog
import com.bizarreelectronics.crm.ui.screens.setup.steps.*

/**
 * §2.10 [plan:L343] — 13-step first-run tenant onboarding wizard.
 *
 * Layout:
 *   - LinearProgressIndicator at top (0/13 → 13/13).
 *   - HorizontalPager with one page per step composable.
 *   - Bottom bar: Back button (disabled on step 0) + Next/Finish button
 *     (disabled while loading; shows "Finish" on the last step).
 *
 * Motion: HorizontalPager animation is skipped when [ReduceMotion.isReduceMotion]
 * returns true (honours system accessibility setting + in-app override pref).
 *
 * Deep link: this composable is reachable from `bizarrecrm://setup` which carries
 * a setup token from a tenant-invite email. The token is validated by the existing
 * setup-token plumbing (commit 413dd81) before routing here.
 *
 * [onSetupComplete] — navigation callback; called when completeSetup() succeeds.
 *                     Caller (AppNavGraph) pops to Dashboard, clearing the back stack.
 *
 * §36.2 — Back gesture triggers [PredictiveBackScaffold] which navigates to the
 * previous step when in progress (step > 0) or calls [onSetupComplete] to dismiss
 * the wizard when on step 0 (after ConfirmDialog confirms skip).
 *
 * §36.2 — "Skip onboarding" TextButton in the TopAppBar shows a [ConfirmDialog]
 * before immediately calling [completeSetup] so the user lands on the dashboard.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SetupWizardScreen(
    onSetupComplete: () -> Unit,
    viewModel: SetupWizardViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    val context = LocalContext.current

    // §36.2 — "Skip onboarding" ConfirmDialog state.
    var showSkipDialog by remember { mutableStateOf(false) }

    // §26.4 — honour system Reduce Motion setting for pager animation.
    val reduceMotion = remember(context) {
        val scale = runCatching {
            Settings.Global.getFloat(
                context.contentResolver,
                Settings.Global.ANIMATOR_DURATION_SCALE,
                1f,
            )
        }.getOrDefault(1f)
        scale == 0f
    }

    // Sync pager position to ViewModel state (ViewModel is source of truth).
    val pagerState = rememberPagerState(
        initialPage = uiState.currentStep,
        pageCount   = { SETUP_WIZARD_TOTAL_STEPS },
    )

    // Keep pager in sync with ViewModel currentStep (e.g. after resume-load).
    LaunchedEffect(uiState.currentStep) {
        val animSpec = if (reduceMotion) tween<Float>(0) else tween<Float>(300)
        if (pagerState.currentPage != uiState.currentStep) {
            pagerState.animateScrollToPage(uiState.currentStep, animationSpec = animSpec)
        }
    }

    // Show errors as snackbars (supplemental to per-step inline error text).
    LaunchedEffect(uiState.error) {
        uiState.error?.let { snackbarHostState.showSnackbar(it) }
    }

    // Consume navigation events.
    LaunchedEffect(Unit) {
        viewModel.events.collect { event ->
            when (event) {
                SetupWizardEvent.NavigateToDashboard -> onSetupComplete()
            }
        }
    }

    // §3.14 L582 — check sample data state when the Finish step first appears.
    LaunchedEffect(uiState.currentStep) {
        if (uiState.currentStep == SETUP_WIZARD_TOTAL_STEPS - 1) {
            viewModel.checkSampleDataState()
        }
    }

    val isLastStep = uiState.currentStep == SETUP_WIZARD_TOTAL_STEPS - 1
    val progress   = (uiState.currentStep + 1).toFloat() / SETUP_WIZARD_TOTAL_STEPS.toFloat()

    // §36.2 — PredictiveBackScaffold: back gesture on step > 0 previews previous
    // step; back gesture on step 0 shows the skip-onboarding ConfirmDialog.
    PredictiveBackScaffold(
        enabled = !uiState.isLoading,
        onBack  = {
            if (uiState.currentStep > 0) {
                viewModel.previousStep()
            } else {
                showSkipDialog = true
            }
        },
    ) { _ ->
        Scaffold(
            snackbarHost = { SnackbarHost(snackbarHostState) },
            topBar = {
                TopAppBar(
                    title = { Text("Setup Wizard") },
                    actions = {
                        // §36.2 — "Skip onboarding" available at any step.
                        TextButton(
                            onClick  = { showSkipDialog = true },
                            enabled  = !uiState.isLoading,
                        ) {
                            Text("Skip")
                        }
                    },
                )
            },
            bottomBar = {
                SetupWizardBottomBar(
                    currentStep  = uiState.currentStep,
                    isLastStep   = isLastStep,
                    isLoading    = uiState.isLoading,
                    onBack       = { viewModel.previousStep() },
                    onNext       = {
                        if (isLastStep) viewModel.completeSetup()
                        else viewModel.nextStep()
                    },
                )
            },
        ) { padding ->
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
            ) {
                LinearProgressIndicator(
                    progress    = { progress },
                    modifier    = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 4.dp),
                )
                Text(
                    text     = "Step ${uiState.currentStep + 1} of $SETUP_WIZARD_TOTAL_STEPS",
                    style    = MaterialTheme.typography.labelSmall,
                    color    = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(start = 16.dp, bottom = 4.dp),
                )

                HorizontalPager(
                    state            = pagerState,
                    modifier         = Modifier.fillMaxSize(),
                    userScrollEnabled = false, // ViewModel controls navigation
                ) { page ->
                    StepContent(
                        step        = page,
                        stepData    = uiState.stepData,
                        allStepData = uiState.stepData,
                        isLoading   = uiState.isLoading,
                        // §36.4 — inline validation error shown inside the active step only.
                        inlineError = if (page == uiState.currentStep) uiState.stepError else null,
                        onDataChange = { fields -> viewModel.updateStepData(fields) },
                        // §3.14 L582 — sample data toggle (Finish step only)
                        sampleDataLoaded   = uiState.sampleDataLoaded,
                        isSampleDataBusy   = uiState.isSampleDataBusy,
                        onLoadSampleData   = { viewModel.loadSampleData() },
                        onClearSampleData  = { viewModel.clearSampleData() },
                    )
                }
            }
        }
    }

    // §36.2 — Skip-onboarding confirmation dialog.
    if (showSkipDialog) {
        ConfirmDialog(
            title        = "Skip setup?",
            message      = "You can complete setup later from the dashboard. Some features may be unavailable until setup is finished.",
            confirmLabel = "Skip",
            onConfirm    = {
                showSkipDialog = false
                viewModel.completeSetup()
            },
            onDismiss    = { showSkipDialog = false },
            isDestructive = false,
        )
    }
}

@Composable
private fun StepContent(
    step: Int,
    stepData: Map<Int, Map<String, Any>>,
    allStepData: Map<Int, Map<String, Any>>,
    isLoading: Boolean,
    // §36.4 — per-step inline validation error; null when no error or page is not active.
    inlineError: String? = null,
    onDataChange: (Map<String, Any>) -> Unit,
    // §3.14 L582 — sample data toggle params (forwarded to FinishStep only)
    sampleDataLoaded: Boolean = false,
    isSampleDataBusy: Boolean = false,
    onLoadSampleData: () -> Unit = {},
    onClearSampleData: () -> Unit = {},
) {
    val data = stepData[step] ?: emptyMap()
    when (step) {
        0  -> WelcomeStep()
        1  -> BusinessInfoStep(data = data, onDataChange = onDataChange, inlineError = inlineError)
        2  -> OwnerAccountStep(data = data, onDataChange = onDataChange, inlineError = inlineError)
        3  -> TaxClassesStep(data = data, onDataChange = onDataChange, inlineError = inlineError)
        4  -> PaymentMethodsStep(data = data, onDataChange = onDataChange, inlineError = inlineError)
        5  -> SmsEmailStep(data = data, onDataChange = onDataChange)
        6  -> LabelsStatusesStep(data = data, onDataChange = onDataChange)
        7  -> StaffInviteStep(data = data, onDataChange = onDataChange)
        8  -> InventoryImportStep(data = data, onDataChange = onDataChange)
        9  -> PrinterSetupStep(data = data, onDataChange = onDataChange)
        10 -> BarcodeScannerStep(data = data, onDataChange = onDataChange)
        11 -> SummaryStep(stepData = allStepData)
        12 -> FinishStep(
            isLoading         = isLoading,
            sampleDataLoaded  = sampleDataLoaded,
            isSampleDataBusy  = isSampleDataBusy,
            onLoadSampleData  = onLoadSampleData,
            onClearSampleData = onClearSampleData,
        )
        else -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Text("Unknown step $step")
        }
    }
}

@Composable
private fun SetupWizardBottomBar(
    currentStep: Int,
    isLastStep: Boolean,
    isLoading: Boolean,
    onBack: () -> Unit,
    onNext: () -> Unit,
) {
    Surface(
        shadowElevation = 8.dp,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            modifier = Modifier
                .navigationBarsPadding()
                .padding(horizontal = 16.dp, vertical = 12.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            OutlinedButton(
                onClick  = onBack,
                enabled  = currentStep > 0 && !isLoading,
            ) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                Spacer(Modifier.width(4.dp))
                Text("Back")
            }

            Button(
                onClick  = onNext,
                enabled  = !isLoading,
            ) {
                if (isLoading) {
                    CircularProgressIndicator(
                        modifier  = Modifier.size(18.dp),
                        strokeWidth = 2.dp,
                        color       = MaterialTheme.colorScheme.onPrimary,
                    )
                } else if (isLastStep) {
                    Icon(Icons.Default.Check, contentDescription = "Finish setup")
                    Spacer(Modifier.width(4.dp))
                    Text("Finish")
                } else {
                    Text("Next")
                    Spacer(Modifier.width(4.dp))
                    Icon(Icons.AutoMirrored.Filled.ArrowForward, contentDescription = "Next step")
                }
            }
        }
    }
}
