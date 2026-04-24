package com.bizarreelectronics.crm.ui.screens.checkin.entry

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel

/**
 * Pre-step screen that collects customer + device info before launching
 * the 6-step [com.bizarreelectronics.crm.ui.screens.checkin.CheckInHostScreen].
 *
 * Step 1 — Customer: search / create-new / walk-in / recent chips.
 * Step 2 — Device: model (required) + IMEI/serial + notes.
 *
 * On "Start check-in →" the caller navigates to Screen.CheckIn with
 * deviceId=0L (sentinel: not yet persisted — CheckInViewModel creates the
 * device row when the ticket is finalised).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CheckInEntryScreen(
    onCancel: () -> Unit,
    onStartCheckIn: (customerId: Long, customerName: String, deviceName: String) -> Unit,
    preFillCustomerId: Long = -1L,
    viewModel: CheckInEntryViewModel = hiltViewModel(),
) {
    val step1 by viewModel.step1.collectAsState()
    val step2 by viewModel.step2.collectAsState()
    val currentStep by viewModel.currentStep.collectAsState()

    // Pre-fill once when launched from CustomerDetail with a customerId arg.
    // viewModel.preFillCustomer guards against repeat / invalid ids so this
    // is safe on recomposition.
    LaunchedEffect(preFillCustomerId) {
        if (preFillCustomerId > 0L) viewModel.preFillCustomer(preFillCustomerId)
    }

    Scaffold(
        topBar = {
            CheckInEntryTopBar(
                currentStep = currentStep,
                onBack = { if (currentStep == 0) onCancel() else viewModel.goBack() },
            )
        },
        bottomBar = {
            CheckInEntryBottomBar(
                currentStep = currentStep,
                // Read from the collected state (step1/step2) — NOT from the
                // VM's plain-getter properties — so recomposition kicks in
                // when attachedCustomer / deviceModel change. Reading via
                // `viewModel.canAdvanceStep1` took a non-Compose-tracked
                // snapshot that left the button stuck-disabled after
                // attachCustomer() or attachWalkIn().
                canAdvance = if (currentStep == 0) step1.attachedCustomer != null
                             else step2.deviceModel.isNotBlank(),
                onAdvance = {
                    if (currentStep == 0) {
                        viewModel.advance()
                    } else {
                        val customer = step1.attachedCustomer ?: return@CheckInEntryBottomBar
                        val deviceName = step2.deviceModel.trim()
                        onStartCheckIn(customer.id, customer.name, deviceName)
                    }
                },
            )
        },
    ) { paddingValues ->
        when (currentStep) {
            0 -> Step1CustomerContent(
                state = step1,
                paddingValues = paddingValues,
                onQueryChange = viewModel::onQueryChange,
                onSelectCustomer = viewModel::attachCustomer,
                onAttachRecent = { viewModel.attachCustomer(
                    com.bizarreelectronics.crm.data.remote.dto.CustomerListItem(
                        id = it.id,
                        firstName = it.name.substringBefore(" "),
                        lastName = it.name.substringAfter(" ", "").ifBlank { null },
                        email = it.email,
                        phone = it.phone,
                        mobile = null,
                        organization = null,
                        city = null,
                        state = null,
                        customerGroupName = null,
                        createdAt = null,
                        ticketCount = it.ticketCount,
                    )
                ) },
                onWalkIn = viewModel::attachWalkIn,
                onDetach = viewModel::detachCustomer,
                onShowCreate = viewModel::showCreateNewForm,
                onHideCreate = viewModel::hideCreateNewForm,
                onNewFirstName = viewModel::onNewFirstNameChange,
                onNewLastName = viewModel::onNewLastNameChange,
                onNewPhone = viewModel::onNewPhoneChange,
                onNewEmail = viewModel::onNewEmailChange,
                onSubmitNew = viewModel::submitNewCustomer,
            )
            1 -> Step2DeviceContent(
                state = step2,
                paddingValues = paddingValues,
                onDeviceModelChange = viewModel::onDeviceModelChange,
                onImeiSerialChange = viewModel::onImeiSerialChange,
                onNotesChange = viewModel::onNotesChange,
            )
        }
    }
}

// ─── Top bar ─────────────────────────────────────────────────────────────────

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CheckInEntryTopBar(currentStep: Int, onBack: () -> Unit) {
    val label = if (currentStep == 0) "1 of 2 · Customer" else "2 of 2 · Device"
    TopAppBar(
        title = {
            Column {
                Text("Check-in", style = MaterialTheme.typography.titleMedium)
                Text(
                    label,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
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

// ─── Bottom bar ───────────────────────────────────────────────────────────────

@Composable
private fun CheckInEntryBottomBar(
    currentStep: Int,
    canAdvance: Boolean,
    onAdvance: () -> Unit,
) {
    val label = if (currentStep == 1) "Start check-in →" else "Next — Device info"
    Button(
        onClick = onAdvance,
        enabled = canAdvance,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp)
            .semantics { contentDescription = label },
    ) {
        Text(label)
    }
}

// ─── Step 1: Customer ─────────────────────────────────────────────────────────

@Composable
private fun Step1CustomerContent(
    state: EntryStep1State,
    paddingValues: PaddingValues,
    onQueryChange: (String) -> Unit,
    onSelectCustomer: (com.bizarreelectronics.crm.data.remote.dto.CustomerListItem) -> Unit,
    onAttachRecent: (AttachedCustomerEntry) -> Unit,
    onWalkIn: () -> Unit,
    onDetach: () -> Unit,
    onShowCreate: () -> Unit,
    onHideCreate: () -> Unit,
    onNewFirstName: (String) -> Unit,
    onNewLastName: (String) -> Unit,
    onNewPhone: (String) -> Unit,
    onNewEmail: (String) -> Unit,
    onSubmitNew: () -> Unit,
) {
    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(paddingValues)
            .padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        contentPadding = PaddingValues(top = 16.dp, bottom = 32.dp),
    ) {
        // Attached customer banner
        state.attachedCustomer?.let { customer ->
            item {
                AttachedCustomerBanner(customer = customer, onDetach = onDetach)
            }
        }

        // Recent customers chip strip (only when none attached + recents exist)
        if (state.attachedCustomer == null && state.recent.isNotEmpty()) {
            item {
                Text(
                    "RECENT",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(Modifier.height(4.dp))
                LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(state.recent) { c ->
                        FilterChip(
                            selected = false,
                            onClick = { onAttachRecent(c) },
                            label = { Text(c.name) },
                            modifier = Modifier.semantics { contentDescription = "Select recent customer ${c.name}" },
                        )
                    }
                }
            }
        }

        // Search field (hidden once attached)
        if (state.attachedCustomer == null && !state.isCreatingNew) {
            item {
                OutlinedTextField(
                    value = state.query,
                    onValueChange = onQueryChange,
                    label = { Text("Search customers") },
                    placeholder = { Text("Name, phone, or email") },
                    leadingIcon = {
                        Icon(Icons.Outlined.Search, contentDescription = "Search")
                    },
                    trailingIcon = {
                        if (state.query.isNotEmpty()) {
                            IconButton(
                                onClick = { onQueryChange("") },
                                modifier = Modifier.semantics { contentDescription = "Clear search" },
                            ) {
                                Icon(Icons.Filled.Close, contentDescription = null)
                            }
                        }
                    },
                    keyboardOptions = KeyboardOptions(
                        imeAction = ImeAction.Search,
                        keyboardType = KeyboardType.Text,
                    ),
                    singleLine = true,
                    modifier = Modifier
                        .fillMaxWidth()
                        .semantics { contentDescription = "Search customers field" },
                )
            }

            // Search spinner / results
            if (state.isSearching) {
                item {
                    Box(
                        modifier = Modifier.fillMaxWidth().padding(16.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(24.dp).semantics { contentDescription = "Searching" },
                        )
                    }
                }
            } else if (state.results.isNotEmpty()) {
                items(state.results) { customer ->
                    CustomerSearchRow(customer = customer, onClick = { onSelectCustomer(customer) })
                    HorizontalDivider()
                }
            }

            // "Create new" text button
            item {
                TextButton(
                    onClick = onShowCreate,
                    modifier = Modifier.semantics { contentDescription = "Create new customer" },
                ) {
                    Text("+ Create new customer")
                }
            }

            // Walk-in ghost tile — dashed-border per GhostWalkInTile pattern
            // (inline; no util extracted per single-file preference).
            item { WalkInTile(onWalkIn = onWalkIn) }
        }

        // Inline create-new form
        if (state.isCreatingNew) {
            item {
                CreateNewCustomerForm(
                    state = state,
                    onFirstName = onNewFirstName,
                    onLastName = onNewLastName,
                    onPhone = onNewPhone,
                    onEmail = onNewEmail,
                    onSubmit = onSubmitNew,
                    onCancel = onHideCreate,
                )
            }
        }
    }
}

// ─── Step 2: Device ───────────────────────────────────────────────────────────

@Composable
private fun Step2DeviceContent(
    state: EntryStep2State,
    paddingValues: PaddingValues,
    onDeviceModelChange: (String) -> Unit,
    onImeiSerialChange: (String) -> Unit,
    onNotesChange: (String) -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(paddingValues)
            .padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Spacer(Modifier.height(4.dp))

        OutlinedTextField(
            value = state.deviceModel,
            onValueChange = onDeviceModelChange,
            label = { Text("Device model *") },
            placeholder = { Text("e.g. iPhone 15 Pro") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(
                capitalization = KeyboardCapitalization.Words,
                imeAction = ImeAction.Next,
            ),
            modifier = Modifier
                .fillMaxWidth()
                .semantics { contentDescription = "Device model field, required" },
        )

        OutlinedTextField(
            value = state.imeiSerial,
            onValueChange = onImeiSerialChange,
            label = { Text("IMEI / Serial (optional)") },
            placeholder = { Text("15-digit IMEI or S/N") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(
                keyboardType = KeyboardType.Number,
                imeAction = ImeAction.Next,
            ),
            textStyle = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace),
            modifier = Modifier
                .fillMaxWidth()
                .semantics { contentDescription = "IMEI or serial number field, optional" },
        )

        OutlinedTextField(
            value = state.notes,
            onValueChange = onNotesChange,
            label = { Text("Color / capacity note (optional)") },
            placeholder = { Text("e.g. Space Black 256 GB") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(
                capitalization = KeyboardCapitalization.Sentences,
                imeAction = ImeAction.Done,
            ),
            modifier = Modifier
                .fillMaxWidth()
                .semantics { contentDescription = "Color or capacity note field, optional" },
        )
    }
}

// ─── Sub-composables ──────────────────────────────────────────────────────────

@Composable
private fun AttachedCustomerBanner(customer: AttachedCustomerEntry, onDetach: () -> Unit) {
    Surface(
        shape = RoundedCornerShape(12.dp),
        color = MaterialTheme.colorScheme.secondaryContainer,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Box(
                modifier = Modifier
                    .size(36.dp)
                    .clip(CircleShape)
                    .background(MaterialTheme.colorScheme.secondary),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    customer.name.take(2).uppercase(),
                    style = MaterialTheme.typography.labelSmall,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.onSecondary,
                )
            }
            Column(modifier = Modifier.weight(1f)) {
                Text(customer.name, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                customer.phone?.let { ph ->
                    Text(
                        "$ph · ${customer.ticketCount} tickets",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            Icon(
                Icons.Filled.Check,
                contentDescription = "Customer attached",
                tint = MaterialTheme.colorScheme.secondary,
            )
            IconButton(
                onClick = onDetach,
                modifier = Modifier.semantics { contentDescription = "Remove attached customer" },
            ) {
                Icon(Icons.Filled.Close, contentDescription = null)
            }
        }
    }
}

@Composable
private fun CustomerSearchRow(
    customer: com.bizarreelectronics.crm.data.remote.dto.CustomerListItem,
    onClick: () -> Unit,
) {
    val displayName = listOfNotNull(customer.firstName, customer.lastName)
        .joinToString(" ")
        .ifBlank { "Customer #${customer.id}" }
    val initials = displayName.take(2).uppercase()
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClickLabel = "Select $displayName") { onClick() }
            .defaultMinSize(minHeight = 48.dp)
            .padding(horizontal = 4.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Box(
            modifier = Modifier
                .size(32.dp)
                .clip(CircleShape)
                .background(MaterialTheme.colorScheme.tertiary),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                initials,
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onTertiary,
            )
        }
        Column(modifier = Modifier.weight(1f)) {
            Text(displayName, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
            val sub = listOfNotNull(customer.phone ?: customer.mobile, customer.email).joinToString(" · ")
            if (sub.isNotEmpty()) {
                Text(sub, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        customer.ticketCount?.takeIf { it > 0 }?.let {
            Text(
                "$it tickets",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

/** Walk-in "ghost" dashed-border tile. Pattern mirrors GhostWalkInTile in PosEntryScreen. */
@Composable
private fun WalkInTile(onWalkIn: () -> Unit) {
    val dashedColor = MaterialTheme.colorScheme.outline
    val shape = RoundedCornerShape(14.dp)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .clickable(onClickLabel = "Walk-in — no customer record") { onWalkIn() }
            .drawBehind {
                // Dashed outline via drawBehind + Stroke.dashPathEffect.
                // No Modifier.dashedBorder helper in Compose; inline avoids an
                // extra util file for a one-off.
                val strokeWidth = 1.5.dp.toPx()
                val dashEffect = PathEffect.dashPathEffect(floatArrayOf(12f, 8f), 0f)
                drawRoundRect(
                    color = dashedColor,
                    size = Size(size.width - strokeWidth, size.height - strokeWidth),
                    topLeft = Offset(strokeWidth / 2, strokeWidth / 2),
                    cornerRadius = CornerRadius(14.dp.toPx() - strokeWidth / 2),
                    style = Stroke(width = strokeWidth, pathEffect = dashEffect),
                )
            }
            .padding(horizontal = 16.dp, vertical = 14.dp)
            .defaultMinSize(minHeight = 60.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Box(
            modifier = Modifier
                .size(44.dp)
                .drawBehind {
                    val strokeWidth = 1.5.dp.toPx()
                    val dashEffect = PathEffect.dashPathEffect(floatArrayOf(8f, 6f), 0f)
                    drawRoundRect(
                        color = dashedColor,
                        size = Size(size.width - strokeWidth, size.height - strokeWidth),
                        topLeft = Offset(strokeWidth / 2, strokeWidth / 2),
                        cornerRadius = CornerRadius(12.dp.toPx()),
                        style = Stroke(width = strokeWidth, pathEffect = dashEffect),
                    )
                },
            contentAlignment = Alignment.Center,
        ) {
            Text("👥", style = MaterialTheme.typography.titleMedium)
        }
        Column(modifier = Modifier.weight(1f)) {
            Text(
                "Walk-in customer",
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                "No customer record · quick check-in",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Text("›", color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun CreateNewCustomerForm(
    state: EntryStep1State,
    onFirstName: (String) -> Unit,
    onLastName: (String) -> Unit,
    onPhone: (String) -> Unit,
    onEmail: (String) -> Unit,
    onSubmit: () -> Unit,
    onCancel: () -> Unit,
) {
    Surface(
        shape = RoundedCornerShape(14.dp),
        tonalElevation = 2.dp,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("New customer", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                IconButton(
                    onClick = onCancel,
                    modifier = Modifier.semantics { contentDescription = "Cancel new customer form" },
                ) {
                    Icon(Icons.Filled.Close, contentDescription = null)
                }
            }

            OutlinedTextField(
                value = state.newFirstName,
                onValueChange = onFirstName,
                label = { Text("First name *") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(
                    capitalization = KeyboardCapitalization.Words,
                    imeAction = ImeAction.Next,
                ),
                isError = state.createError != null && state.newFirstName.isBlank(),
                modifier = Modifier
                    .fillMaxWidth()
                    .semantics { contentDescription = "First name field, required" },
            )

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = state.newLastName,
                    onValueChange = onLastName,
                    label = { Text("Last name") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(
                        capitalization = KeyboardCapitalization.Words,
                        imeAction = ImeAction.Next,
                    ),
                    modifier = Modifier
                        .weight(1f)
                        .semantics { contentDescription = "Last name field, optional" },
                )
            }

            OutlinedTextField(
                value = state.newPhone,
                onValueChange = onPhone,
                label = { Text("Phone") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.Phone,
                    imeAction = ImeAction.Next,
                ),
                modifier = Modifier
                    .fillMaxWidth()
                    .semantics { contentDescription = "Phone number field, optional" },
            )

            OutlinedTextField(
                value = state.newEmail,
                onValueChange = onEmail,
                label = { Text("Email") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.Email,
                    imeAction = ImeAction.Done,
                ),
                modifier = Modifier
                    .fillMaxWidth()
                    .semantics { contentDescription = "Email address field, optional" },
            )

            state.createError?.let { err ->
                Text(
                    err,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.semantics { contentDescription = "Error: $err" },
                )
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                TextButton(onClick = onCancel) { Text("Cancel") }
                Spacer(Modifier.width(8.dp))
                Button(
                    onClick = onSubmit,
                    enabled = !state.isCreating && state.newFirstName.isNotBlank(),
                    modifier = Modifier.semantics { contentDescription = "Create customer" },
                ) {
                    if (state.isCreating) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(16.dp),
                            strokeWidth = 2.dp,
                            color = MaterialTheme.colorScheme.onPrimary,
                        )
                    } else {
                        Text("Create")
                    }
                }
            }
        }
    }
}
