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
import androidx.compose.material.icons.filled.DevicesOther
import androidx.compose.material.icons.filled.Headphones
import androidx.compose.material.icons.filled.Laptop
import androidx.compose.material.icons.filled.Print
import androidx.compose.material.icons.filled.Smartphone
import androidx.compose.material.icons.filled.SportsEsports
import androidx.compose.material.icons.filled.TabletAndroid
import androidx.compose.material.icons.filled.Tv
import androidx.compose.material.icons.filled.Watch
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.LinearWavyProgressIndicator
import androidx.compose.material3.LoadingIndicator
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

    // Pre-fill once when launched with a customerId arg. Sentinels:
    //   -1L → bare route, no pre-fill (default in nav graph)
    //    0L → walk-in pre-fill (POS attached walk-in)
    //   >0L → real customer pre-fill
    // viewModel.preFillCustomer guards against repeat calls so this is
    // safe on recomposition.
    LaunchedEffect(preFillCustomerId) {
        if (preFillCustomerId >= 0L) viewModel.preFillCustomer(preFillCustomerId)
    }

    // 2026-04-26 — fix flicker: when launched with a preFillCustomerId, the
    // VM defaults currentStep=0 (Customer) and only advances after the async
    // fetch completes — so users saw a 1-frame flash of the Customer screen
    // before it switched to Device. Treat the step as already-1 from the
    // first frame; once the VM advances, currentStep == 1 anyway.
    val effectiveStep = if (
        preFillCustomerId >= 0L &&
        currentStep == 0 &&
        step1.attachedCustomer == null
    ) 1 else currentStep

    val ctaLabel = if (effectiveStep == 1) "Start check-in →" else "Next — Device info"
    val canAdvance = if (effectiveStep == 0) step1.attachedCustomer != null
                     else step2.deviceModel.isNotBlank()
    com.bizarreelectronics.crm.ui.components.shared.PosFlowScaffold(
        title = "Check-in",
        subtitle = if (effectiveStep == 0) "Step 2 of 8 · Customer" else "Step 3 of 8 · Device",
        // entry/0 customer = step 2; entry/1 device = step 3 (POS Home is step 1).
        stepIndex = effectiveStep + 1,
        totalSteps = 8,
        onBack = { if (effectiveStep == 0) onCancel() else viewModel.goBack() },
        bottomBar = {
            Button(
                onClick = {
                    if (effectiveStep == 0) {
                        viewModel.advance()
                    } else {
                        val customer = step1.attachedCustomer ?: return@Button
                        val deviceName = step2.deviceModel.trim()
                        onStartCheckIn(customer.id, customer.name, deviceName)
                    }
                },
                enabled = canAdvance,
                modifier = Modifier
                    .fillMaxWidth()
                    .semantics { contentDescription = ctaLabel },
            ) {
                Text(ctaLabel)
            }
        },
    ) { paddingValues ->
        Column(modifier = Modifier.fillMaxSize().padding(paddingValues)) {
        when (effectiveStep) {
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
                onSelectOnFileDevice = viewModel::selectOnFileDevice,
                onAddNewDevice = viewModel::toggleManualEntry,
                onDeviceTypeSelected = viewModel::onDeviceTypeSelected,
                onManufacturerSelected = viewModel::onManufacturerSelected,
                onModelSelected = viewModel::onModelSelected,
                onDrillBack = viewModel::onDrillBack,
            )
        }
        } // close Column
    }
}

// Top + bottom bar moved to PosFlowScaffold (see ui/components/shared/PosFlowScaffold.kt)
// for cohesive POS-to-Ticket chrome — same wave/back/CTA shape across all flow screens.

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
    // Outer Column already applies paddingValues — don't double-count.
    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
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
                        @OptIn(ExperimentalMaterial3ExpressiveApi::class)
                        LoadingIndicator(
                            modifier = Modifier.size(40.dp).semantics { contentDescription = "Searching" },
                        )
                    }
                }
            } else if (state.results.isNotEmpty()) {
                items(state.results) { customer ->
                    CustomerSearchRow(customer = customer, onClick = { onSelectCustomer(customer) })
                    HorizontalDivider()
                }
            }

            // "Create new customer" tile — primary-bordered per mockup,
            // with a cream-filled "+" icon box. Replaces the earlier bare
            // TextButton that looked orphaned between the search field and
            // the walk-in ghost tile.
            item { CreateNewCustomerTile(onClick = onShowCreate) }

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
    onSelectOnFileDevice: (Long) -> Unit = {},
    onAddNewDevice: () -> Unit = {},
    onDeviceTypeSelected: (String?) -> Unit = {},
    onManufacturerSelected: (Long?) -> Unit = {},
    onModelSelected: (com.bizarreelectronics.crm.data.remote.dto.DeviceModelItem) -> Unit = {},
    onDrillBack: () -> Unit = {},
) {
    // Outer Column in CheckInEntryScreen already applies paddingValues from
    // PosFlowScaffold. Re-applying here would double-count the top/bottom
    // bar inset and squeeze content (top empty + bottom rows covered by
    // shelf). Use fillMaxSize only; safe scroll buffer via contentPadding.
    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
        contentPadding = PaddingValues(top = 12.dp, bottom = 24.dp),
    ) {
        // Mockup PHONE 2 'ON FILE · N' header + selectable rows.
        if (state.onFileDevices.isNotEmpty()) {
            item {
                Text(
                    "ON FILE · ${state.onFileDevices.size}",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 4.dp, bottom = 4.dp),
                )
            }
            items(state.onFileDevices, key = { it.id }) { device ->
                OnFileDeviceRow(
                    device = device,
                    selected = device.id == state.selectedOnFileDeviceId,
                    onClick = { onSelectOnFileDevice(device.id) },
                )
            }
        }

        // Mockup PHONE 2 'ADD NEW' header + dashed-primary 'Add new device' tile.
        item {
            Text(
                "ADD NEW",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 12.dp, bottom = 4.dp),
            )
        }
        item {
            AddNewDeviceTile(
                expanded = state.showManualEntry,
                onClick = onAddNewDevice,
            )
        }

        // Manual-entry text fields appear only after the cashier toggles
        // 'Add new device' or selects nothing. Stays as a 3-field stack so
        // the existing text-field layout doesn't regress.
        if (state.showManualEntry) {
            // 2026-04-27 — drill-down: CATEGORY tiles → MANUFACTURER tiles → MODEL tiles → DETAILS fields.
            // Each step renders a 2-column tile grid matching the issue-tile mockup
            // (ios/pos-phone-mockups.html). Back chip on non-root steps reverts one level.
            val drillHeader = when (state.drillStep) {
                com.bizarreelectronics.crm.ui.screens.checkin.entry.DeviceDrillStep.CATEGORY -> "TYPE"
                com.bizarreelectronics.crm.ui.screens.checkin.entry.DeviceDrillStep.MANUFACTURER -> "MAKE"
                com.bizarreelectronics.crm.ui.screens.checkin.entry.DeviceDrillStep.MODEL -> "MODEL"
                com.bizarreelectronics.crm.ui.screens.checkin.entry.DeviceDrillStep.DETAILS -> "DEVICE"
            }
            item {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    if (state.drillStep != com.bizarreelectronics.crm.ui.screens.checkin.entry.DeviceDrillStep.CATEGORY) {
                        IconButton(onClick = onDrillBack, modifier = Modifier.size(32.dp)) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", modifier = Modifier.size(18.dp))
                        }
                        Spacer(Modifier.width(4.dp))
                    }
                    Text(
                        drillHeader,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(top = 4.dp),
                    )
                }
            }
            // CATEGORY tile grid
            if (state.drillStep == com.bizarreelectronics.crm.ui.screens.checkin.entry.DeviceDrillStep.CATEGORY) {
                item {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        state.deviceCategories.chunked(2).forEach { row ->
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                row.forEach { cat ->
                                    DeviceTypeTile(
                                        slug = cat.slug,
                                        label = cat.label,
                                        selected = state.selectedDeviceType == cat.slug,
                                        onClick = { onDeviceTypeSelected(cat.slug) },
                                        modifier = Modifier.weight(1f),
                                    )
                                }
                                if (row.size == 1) Spacer(Modifier.weight(1f))
                            }
                        }
                    }
                }
            }
            // MANUFACTURER tile grid
            if (state.drillStep == com.bizarreelectronics.crm.ui.screens.checkin.entry.DeviceDrillStep.MANUFACTURER) {
                if (state.drillLoading) {
                    item {
                        Box(modifier = Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) {
                            Text("Loading…", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                } else if (state.manufacturers.isEmpty()) {
                    item {
                        Text(
                            state.drillError ?: "No manufacturers found for this category.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(vertical = 12.dp),
                        )
                    }
                } else {
                    item {
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            state.manufacturers.chunked(2).forEach { row ->
                                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    row.forEach { m ->
                                        ManufacturerTile(
                                            label = m.name,
                                            modelCount = m.modelCount,
                                            selected = state.selectedManufacturerId == m.id,
                                            onClick = { onManufacturerSelected(m.id) },
                                            modifier = Modifier.weight(1f),
                                        )
                                    }
                                    if (row.size == 1) Spacer(Modifier.weight(1f))
                                }
                            }
                        }
                    }
                }
            }
            // MODEL tile grid
            if (state.drillStep == com.bizarreelectronics.crm.ui.screens.checkin.entry.DeviceDrillStep.MODEL) {
                if (state.drillLoading) {
                    item {
                        Box(modifier = Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) {
                            Text("Loading…", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                } else if (state.models.isEmpty()) {
                    item {
                        Text(
                            state.drillError ?: "No models found.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(vertical = 12.dp),
                        )
                    }
                } else {
                    item {
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            state.models.chunked(2).forEach { row ->
                                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    row.forEach { m ->
                                        ModelTile(
                                            label = m.name,
                                            year = m.releaseYear,
                                            onClick = { onModelSelected(m) },
                                            modifier = Modifier.weight(1f),
                                        )
                                    }
                                    if (row.size == 1) Spacer(Modifier.weight(1f))
                                }
                            }
                        }
                    }
                }
            }
            // DETAILS — show device-model field (pre-filled) + IMEI + notes only after drill complete.
            if (state.drillStep == com.bizarreelectronics.crm.ui.screens.checkin.entry.DeviceDrillStep.DETAILS) {
                item {
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
                            .padding(top = 8.dp)
                            .semantics { contentDescription = "Device model field, required" },
                    )
                }
            item {
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
            }
            item {
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
            } // close DETAILS step
        }
    }
}

/**
 * Device-type picker tile (mockup parity: ios/pos-phone-mockups.html issues
 * grid). 2-col grid item, surface bg, cream primary border 1.5dp on select,
 * outline 1dp idle, RoundedCornerShape(10dp), padding 12dp, 96dp tall.
 * Icon picked from Material from category slug; falls back to DevicesOther.
 */
@Composable
private fun DeviceTypeTile(
    slug: String,
    label: String,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val borderColor = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline
    val borderWidth = if (selected) 1.5.dp else 1.dp
    val labelColor = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface
    val iconTint = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant
    val icon = when (slug) {
        "phone", "smartphone" -> Icons.Filled.Smartphone
        "tablet" -> Icons.Filled.TabletAndroid
        "laptop" -> Icons.Filled.Laptop
        "desktop" -> Icons.Filled.Print
        "tv" -> Icons.Filled.Tv
        "game-console", "console" -> Icons.Filled.SportsEsports
        "watch", "smartwatch" -> Icons.Filled.Watch
        "drone" -> Icons.Filled.DevicesOther
        "headphones" -> Icons.Filled.Headphones
        else -> Icons.Filled.DevicesOther
    }
    Surface(
        modifier = modifier
            .height(96.dp)
            .border(borderWidth, borderColor, RoundedCornerShape(10.dp))
            .clickable(onClickLabel = "Select $label") { onClick() },
        shape = RoundedCornerShape(10.dp),
        color = MaterialTheme.colorScheme.surface,
    ) {
        Column(
            modifier = Modifier.padding(12.dp).fillMaxSize(),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = iconTint,
                modifier = Modifier.size(28.dp),
            )
            Spacer(Modifier.height(6.dp))
            Text(
                text = label,
                style = MaterialTheme.typography.labelMedium,
                fontWeight = androidx.compose.ui.text.font.FontWeight.Bold,
                color = labelColor,
            )
        }
    }
}

/** Manufacturer drill tile — same dimensions as DeviceTypeTile but no icon (text-only). */
@Composable
private fun ManufacturerTile(
    label: String,
    modelCount: Int,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val borderColor = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline
    val borderWidth = if (selected) 1.5.dp else 1.dp
    val labelColor = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface
    Surface(
        modifier = modifier
            .height(96.dp)
            .border(borderWidth, borderColor, RoundedCornerShape(10.dp))
            .clickable(onClickLabel = "Select $label") { onClick() },
        shape = RoundedCornerShape(10.dp),
        color = MaterialTheme.colorScheme.surface,
    ) {
        Column(
            modifier = Modifier.padding(12.dp).fillMaxSize(),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                text = label,
                style = MaterialTheme.typography.labelLarge,
                fontWeight = androidx.compose.ui.text.font.FontWeight.Bold,
                color = labelColor,
            )
            if (modelCount > 0) {
                Spacer(Modifier.height(2.dp))
                Text(
                    text = "$modelCount models",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

/** Model drill tile — model name + optional release year. */
@Composable
private fun ModelTile(
    label: String,
    year: Int?,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Surface(
        modifier = modifier
            .height(96.dp)
            .border(1.dp, MaterialTheme.colorScheme.outline, RoundedCornerShape(10.dp))
            .clickable(onClickLabel = "Select $label") { onClick() },
        shape = RoundedCornerShape(10.dp),
        color = MaterialTheme.colorScheme.surface,
    ) {
        Column(
            modifier = Modifier.padding(12.dp).fillMaxSize(),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                text = label,
                style = MaterialTheme.typography.labelMedium,
                fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurface,
                maxLines = 2,
            )
            if (year != null) {
                Spacer(Modifier.height(2.dp))
                Text(
                    text = year.toString(),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun OnFileDeviceRow(
    device: com.bizarreelectronics.crm.ui.screens.checkin.entry.OnFileDevice,
    selected: Boolean,
    onClick: () -> Unit,
) {
    val borderColor = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline
    val borderWidth = if (selected) 1.5.dp else 1.dp
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .border(borderWidth, borderColor, RoundedCornerShape(12.dp))
            .background(MaterialTheme.colorScheme.surface)
            .clickable(onClickLabel = "Select ${device.name}") { onClick() }
            .padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(
            modifier = Modifier
                .size(40.dp)
                .clip(RoundedCornerShape(10.dp))
                .background(MaterialTheme.colorScheme.surfaceVariant),
            contentAlignment = Alignment.Center,
        ) {
            Text("📱", style = MaterialTheme.typography.titleMedium)
        }
        Column(modifier = Modifier.weight(1f)) {
            Text(device.name, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Bold)
            val subtitle = listOfNotNull(
                device.imei?.takeIf { it.isNotBlank() }?.let { "IMEI ${it.take(3)}…${it.takeLast(4)}" }
                    ?: device.serial?.takeIf { it.isNotBlank() }?.let { "Serial ${it.take(3)}…${it.takeLast(3)}" },
                device.color?.takeIf { it.isNotBlank() },
                device.notes?.takeIf { it.isNotBlank() },
            ).joinToString(" · ")
            if (subtitle.isNotBlank()) {
                Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        Text(
            if (selected) "●" else "○",
            style = MaterialTheme.typography.titleMedium,
            color = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun AddNewDeviceTile(expanded: Boolean, onClick: () -> Unit) {
    val primary = MaterialTheme.colorScheme.primary
    val shape = RoundedCornerShape(12.dp)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .clickable(onClickLabel = "Add new device") { onClick() }
            .drawBehind {
                val strokeWidth = 1.5.dp.toPx()
                val dash = androidx.compose.ui.graphics.PathEffect.dashPathEffect(floatArrayOf(12f, 8f), 0f)
                drawRoundRect(
                    color = primary,
                    size = androidx.compose.ui.geometry.Size(size.width - strokeWidth, size.height - strokeWidth),
                    topLeft = androidx.compose.ui.geometry.Offset(strokeWidth / 2, strokeWidth / 2),
                    cornerRadius = androidx.compose.ui.geometry.CornerRadius(12.dp.toPx() - strokeWidth / 2),
                    style = androidx.compose.ui.graphics.drawscope.Stroke(width = strokeWidth, pathEffect = dash),
                )
            }
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(
            modifier = Modifier
                .size(40.dp)
                .clip(RoundedCornerShape(10.dp))
                .background(MaterialTheme.colorScheme.primary),
            contentAlignment = Alignment.Center,
        ) {
            Text("+", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Black, color = MaterialTheme.colorScheme.onPrimary)
        }
        Column(modifier = Modifier.weight(1f)) {
            Text("Add new device", style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.primary)
            Text(
                if (expanded) "Fill out details below" else "Pick model, IMEI/serial, condition",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Text(if (expanded) "▾" else "›", color = MaterialTheme.colorScheme.primary)
    }
}

// ─── Sub-composables ──────────────────────────────────────────────────────────

@Composable
private fun AttachedCustomerBanner(customer: AttachedCustomerEntry, onDetach: () -> Unit) {
    val sub = listOfNotNull(
        customer.phone,
        "${customer.ticketCount} ${if (customer.ticketCount == 1) "ticket" else "tickets"}",
    ).joinToString(" · ").ifBlank { null }
    com.bizarreelectronics.crm.ui.components.shared.CustomerHeaderPill(
        name = customer.name,
        subtitle = sub,
        onDetach = onDetach,
    )
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

/** Primary-bordered "Create new customer" tile matching the mockup. */
@Composable
private fun CreateNewCustomerTile(onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .border(
                width = 1.5.dp,
                color = MaterialTheme.colorScheme.primary,
                shape = RoundedCornerShape(14.dp),
            )
            .clickable(onClickLabel = "Create new customer") { onClick() }
            .padding(horizontal = 16.dp, vertical = 14.dp)
            .defaultMinSize(minHeight = 60.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Box(
            modifier = Modifier
                .size(44.dp)
                .clip(RoundedCornerShape(12.dp))
                .background(MaterialTheme.colorScheme.primary),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                "+",
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.ExtraBold,
                color = MaterialTheme.colorScheme.onPrimary,
            )
        }
        Column(modifier = Modifier.weight(1f)) {
            Text(
                "Create new customer",
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.Bold,
            )
            Text(
                "First name required",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Text("›", color = MaterialTheme.colorScheme.onSurfaceVariant)
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
                // §26.1 — supportingText is read by TalkBack when isError=true so the
                // error is announced inline rather than only visible on screen.
                supportingText = if (state.createError != null && state.newFirstName.isBlank()) {
                    { Text("First name is required") }
                } else null,
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
                        @OptIn(ExperimentalMaterial3ExpressiveApi::class)
                        LoadingIndicator(
                            modifier = Modifier.size(20.dp),
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
