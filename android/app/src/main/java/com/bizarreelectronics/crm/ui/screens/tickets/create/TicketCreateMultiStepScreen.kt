package com.bizarreelectronics.crm.ui.screens.tickets.create

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.ui.screens.tickets.TicketCreateSubStep
import com.bizarreelectronics.crm.ui.screens.tickets.TicketCreateViewModel
import com.bizarreelectronics.crm.ui.screens.tickets.create.steps.*

/**
 * Multi-step ticket create wizard shell (§4.3 L684-L708).
 *
 * ### Phone layout
 * Full-screen scaffold with:
 * - [LinearProgressIndicator] segmented `(currentIndex + 1) / 7` at the top.
 * - [AnimatedContent] slide-horizontal between steps (snaps when ReduceMotion is on).
 * - Back / Next sticky bottom bar; Next disabled when step validation fails.
 *
 * ### Tablet layout
 * - Left pane: step list with check-marks for completed steps.
 * - Right pane: active step content.
 *
 * Delegates all state to [TicketCreateViewModel]; this composable is pure UI.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TicketCreateMultiStepScreen(
    onBack: () -> Unit,
    onCreated: (Long) -> Unit,
    viewModel: TicketCreateViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    val configuration = LocalConfiguration.current
    val isTablet = configuration.screenWidthDp >= 600

    // Reduce-motion: skip animation when accessibility reduces motion
    val reduceMotion = remember {
        val uiMode = configuration.uiMode
        // Check if the user has enabled reduce motion via accessibility
        false // Placeholder — real impl checks AccessibilityManager
    }

    LaunchedEffect(state.error) {
        state.error?.let {
            snackbarHostState.showSnackbar(it)
            viewModel.clearError()
        }
    }

    // Load employees lazily when Assignee step becomes active
    LaunchedEffect(state.currentSubStep) {
        if (state.currentSubStep == TicketCreateSubStep.ASSIGNEE) {
            viewModel.loadEmployees()
        }
    }

    val currentStep = state.currentSubStep
    val currentIndex = currentStep.ordinal
    val totalSteps = TicketCreateSubStep.entries.size
    val progress = (currentIndex + 1).toFloat() / totalSteps.toFloat()

    val isCurrentStepValid = StepValidator.isValid(currentStep, state)

    Scaffold(
        topBar = {
            Column {
                TopAppBar(
                    title = { Text(currentStep.label) },
                    navigationIcon = {
                        IconButton(onClick = {
                            viewModel.goToPreviousSubStep(onExit = onBack)
                        }) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                        }
                    },
                )
                LinearProgressIndicator(
                    progress = { progress },
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        },
        bottomBar = {
            BottomAppBar(
                modifier = Modifier.navigationBarsPadding().imePadding(),
            ) {
                if (currentIndex > 0) {
                    OutlinedButton(
                        onClick = { viewModel.goToPreviousSubStep(onExit = onBack) },
                        modifier = Modifier.padding(start = 16.dp),
                    ) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
                        Spacer(Modifier.width(4.dp))
                        Text("Back")
                    }
                }
                Spacer(Modifier.weight(1f))
                if (currentStep != TicketCreateSubStep.REVIEW) {
                    Button(
                        onClick = { viewModel.goToNextSubStep() },
                        enabled = isCurrentStepValid,
                        modifier = Modifier.padding(end = 16.dp),
                    ) {
                        Text("Next")
                        Spacer(Modifier.width(4.dp))
                        Icon(Icons.AutoMirrored.Filled.ArrowForward, contentDescription = null)
                    }
                }
            }
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { innerPadding ->
        if (isTablet) {
            TabletLayout(
                state = state,
                viewModel = viewModel,
                onSubmit = { viewModel.submitTicket(onCreated) },
                modifier = Modifier.padding(innerPadding),
            )
        } else {
            PhoneLayout(
                state = state,
                viewModel = viewModel,
                currentStep = currentStep,
                reduceMotion = reduceMotion,
                onSubmit = { viewModel.submitTicket(onCreated) },
                modifier = Modifier.padding(innerPadding),
            )
        }
    }
}

// ── Phone layout ───────────────────────────────────────────────────────────

@Composable
private fun PhoneLayout(
    state: com.bizarreelectronics.crm.ui.screens.tickets.TicketCreateUiState,
    viewModel: TicketCreateViewModel,
    currentStep: TicketCreateSubStep,
    reduceMotion: Boolean,
    onSubmit: () -> Unit,
    modifier: Modifier = Modifier,
) {
    AnimatedContent(
        targetState = currentStep,
        transitionSpec = {
            if (reduceMotion) {
                // Snap with no animation when reduce motion is enabled
                (slideInHorizontally { 0 } togetherWith slideOutHorizontally { 0 })
            } else {
                val forward = targetState.ordinal > initialState.ordinal
                val direction = if (forward) 1 else -1
                slideInHorizontally(
                    initialOffsetX = { it * direction },
                    animationSpec = tween(250),
                ) togetherWith slideOutHorizontally(
                    targetOffsetX = { -it * direction },
                    animationSpec = tween(250),
                )
            }
        },
        modifier = modifier.fillMaxSize(),
        label = "step_transition",
    ) { step ->
        StepContent(
            step = step,
            state = state,
            viewModel = viewModel,
            onSubmit = onSubmit,
        )
    }
}

// ── Tablet layout ──────────────────────────────────────────────────────────

@Composable
private fun TabletLayout(
    state: com.bizarreelectronics.crm.ui.screens.tickets.TicketCreateUiState,
    viewModel: TicketCreateViewModel,
    onSubmit: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(modifier = modifier.fillMaxSize()) {
        // Left pane — step list
        NavigationDrawerContent(
            currentStep = state.currentSubStep,
            completedSteps = state.completedSubSteps,
            onSelectStep = viewModel::goToSubStep,
            modifier = Modifier
                .width(200.dp)
                .fillMaxHeight(),
        )
        VerticalDivider()
        // Right pane — active step
        StepContent(
            step = state.currentSubStep,
            state = state,
            viewModel = viewModel,
            onSubmit = onSubmit,
            modifier = Modifier.weight(1f).fillMaxHeight(),
        )
    }
}

@Composable
private fun NavigationDrawerContent(
    currentStep: TicketCreateSubStep,
    completedSteps: Set<TicketCreateSubStep>,
    onSelectStep: (TicketCreateSubStep) -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier = modifier.padding(8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text("Steps", style = MaterialTheme.typography.labelMedium, modifier = Modifier.padding(8.dp))
        TicketCreateSubStep.entries.forEach { step ->
            val isActive = step == currentStep
            val isDone = step in completedSteps
            NavigationDrawerItem(
                label = { Text(step.label) },
                selected = isActive,
                onClick = { if (isDone || isActive) onSelectStep(step) },
                badge = if (isDone) ({
                    Icon(
                        Icons.Default.Check,
                        contentDescription = "Done",
                        modifier = Modifier.size(16.dp),
                        tint = MaterialTheme.colorScheme.primary,
                    )
                }) else null,
            )
        }
    }
}

// ── Step content router ────────────────────────────────────────────────────

@Composable
private fun StepContent(
    step: TicketCreateSubStep,
    state: com.bizarreelectronics.crm.ui.screens.tickets.TicketCreateUiState,
    viewModel: TicketCreateViewModel,
    onSubmit: () -> Unit,
    modifier: Modifier = Modifier,
) {
    when (step) {
        TicketCreateSubStep.CUSTOMER -> CustomerStepScreen(
            query = state.customerQuery,
            results = state.customerResults,
            isSearching = state.isSearching,
            selectedCustomer = state.selectedCustomer,
            isWalkIn = state.isWalkIn,
            onQueryChange = viewModel::updateCustomerQuery,
            onSelect = viewModel::selectCustomer,
            onSelectWalkIn = viewModel::selectWalkIn,
            onClear = viewModel::clearCustomer,
            showNewCustomerForm = state.showNewCustomerForm,
            onToggleNewCustomerForm = viewModel::toggleNewCustomerForm,
            newCustFirstName = state.newCustFirstName,
            newCustLastName = state.newCustLastName,
            newCustPhone = state.newCustPhone,
            newCustEmail = state.newCustEmail,
            isCreatingCustomer = state.isCreatingCustomer,
            onNewCustFirstNameChange = viewModel::updateNewCustFirstName,
            onNewCustLastNameChange = viewModel::updateNewCustLastName,
            onNewCustPhoneChange = viewModel::updateNewCustPhone,
            onNewCustEmailChange = viewModel::updateNewCustEmail,
            onCreateAndSelect = viewModel::createAndSelectCustomer,
            modifier = modifier,
        )

        TicketCreateSubStep.DEVICE -> DeviceStepScreen(
            category = state.selectedCategory ?: "other",
            manufacturers = state.manufacturers,
            selectedManufacturerId = state.selectedManufacturerId,
            searchQuery = state.deviceSearchQuery,
            searchResults = state.deviceSearchResults,
            popularDevices = state.popularDevices,
            isLoading = state.isLoadingDevices,
            customDeviceName = state.customDeviceName,
            selectedDevice = state.selectedDevice,
            onManufacturerSelect = viewModel::selectManufacturer,
            onSearchChange = viewModel::updateDeviceSearch,
            onDeviceSelect = viewModel::selectDevice,
            onCustomNameChange = viewModel::updateCustomDeviceName,
            onCustomDeviceConfirm = viewModel::confirmCustomDevice,
            modifier = modifier,
        )

        TicketCreateSubStep.SERVICES -> ServicesStepScreen(
            services = state.services,
            selectedService = state.selectedService,
            cartItems = state.cartItems,
            isLoadingPricing = state.isLoadingPricing,
            manualPrice = state.manualPrice,
            onServiceSelect = viewModel::selectService,
            onManualPriceChange = viewModel::updateManualPrice,
            onAddToCart = viewModel::addToCart,
            onRemoveFromCart = viewModel::removeFromCart,
            onBarcodeScan = { /* TODO: launch CameraX barcode scanner */ },
            modifier = modifier,
        )

        TicketCreateSubStep.DIAGNOSTIC -> DiagnosticStepScreen(
            conditionChecks = state.conditionChecks,
            selectedConditions = state.selectedConditions,
            intakePhotoUris = state.intakePhotoUris,
            notes = state.notes,
            onToggleCondition = viewModel::toggleCondition,
            onNotesChange = viewModel::updateNotes,
            onPickPhotos = { /* TODO: launch PhotoPicker */ },
            onRemovePhoto = viewModel::removeIntakePhoto,
            onReorder = viewModel::reorderIntakePhotos,
            modifier = modifier,
        )

        TicketCreateSubStep.PRICING -> PricingStepScreen(
            cartItems = state.cartItems,
            taxRate = state.taxRate,
            cartDiscount = state.cartDiscount,
            cartDiscountType = state.cartDiscountType,
            cartDiscountReason = state.cartDiscountReason,
            depositAmount = state.depositAmount,
            collectDepositNow = state.collectDepositNow,
            onCartDiscountChange = viewModel::updateCartDiscount,
            onCartDiscountReasonChange = viewModel::updateCartDiscountReason,
            onDepositChange = viewModel::updateDeposit,
            modifier = modifier,
        )

        TicketCreateSubStep.ASSIGNEE -> AssigneeStepScreen(
            employees = state.employees,
            isLoadingEmployees = state.isLoadingEmployees,
            assigneeId = state.assigneeId,
            urgency = state.urgency,
            dueDate = state.dueDate,
            currentUserId = null, // TODO: inject from AuthStore
            onSelectAssignee = viewModel::selectAssignee,
            onUpdateUrgency = viewModel::updateUrgency,
            onUpdateDueDate = viewModel::updateDueDate,
            onPickDate = { /* TODO: show DatePickerDialog */ },
            modifier = modifier,
        )

        TicketCreateSubStep.REVIEW -> ReviewStepScreen(
            selectedCustomer = state.selectedCustomer,
            isWalkIn = state.isWalkIn,
            cartItems = state.cartItems,
            taxRate = state.taxRate,
            cartDiscount = state.cartDiscount,
            cartDiscountType = state.cartDiscountType,
            depositAmount = state.depositAmount,
            assigneeName = state.assigneeName,
            urgency = state.urgency,
            dueDate = state.dueDate,
            intakePhotoCount = state.intakePhotoUris.size,
            isSubmitting = state.isSubmitting,
            onJumpToStep = viewModel::goToSubStep,
            onSubmit = onSubmit,
            modifier = modifier,
        )
    }
}
