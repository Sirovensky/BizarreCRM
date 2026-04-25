package com.bizarreelectronics.crm.ui.screens.pos

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.Spring
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.PhotoCamera
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.ui.theme.LocalExtendedColors

/**
 * POS entry screen: path picker + ready-for-pickup hero + animated SearchBar.
 *
 * SearchBar uses M3's built-in active/expanded state so the bottom→top
 * animation and keyboard coordination are handled by the framework — no
 * custom animation math needed.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PosEntryScreen(
    onNavigateToCart: () -> Unit,
    onNavigateToCheckin: (Long?) -> Unit,
    onNavigateToTender: () -> Unit,
    viewModel: PosEntryViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsState()
    var searchExpanded by rememberSaveable { mutableStateOf(false) }

    BackHandler(enabled = searchExpanded) { searchExpanded = false }

    // statusBarsPadding pushes the entire POS-entry surface below the
    // system status bar so the customer banner / clock no longer overlap.
    Box(modifier = Modifier.fillMaxSize().statusBarsPadding()) {
        // ── Content layer ───────────────────────────────────────────────────
        AnimatedVisibility(
            visible = !searchExpanded,
            enter = fadeIn(spring(stiffness = Spring.StiffnessMediumLow)),
            exit = fadeOut(spring(stiffness = Spring.StiffnessMediumLow)),
        ) {
            EntryContent(
                state = state,
                onRetailSale = onNavigateToCart,
                onRepairTicket = { onNavigateToCheckin(state.attachedCustomer?.id?.takeIf { it > 0L }) },
                onStoreCredit = onNavigateToCart,
                onOpenPickup = { ticketId ->
                    // Mockup PHONE 1 'Open cart →' hero pill: skip the cart
                    // step entirely; the line is seeded by the VM and we
                    // jump straight to Tender so the cashier can charge.
                    viewModel.openReadyForPickup(ticketId)
                    onNavigateToTender()
                },
                onWalkIn = {
                    viewModel.attachWalkIn()
                    onNavigateToCart()
                },
            )
        }

        // ── M3 SearchBar: docked at bottom when collapsed, top when active ──
        SearchBar(
            query = state.searchQuery,
            onQueryChange = viewModel::onQueryChange,
            onSearch = {},
            active = searchExpanded,
            onActiveChange = { searchExpanded = it },
            placeholder = { Text("Customer, part, or ticket…") },
            leadingIcon = {
                Icon(
                    Icons.Outlined.Search,
                    contentDescription = "Search",
                )
            },
            trailingIcon = {
                IconButton(
                    onClick = { /* barcode scanner — wired in cart screen */ },
                    modifier = Modifier.semantics { contentDescription = "Scan barcode" },
                ) {
                    Icon(Icons.Outlined.PhotoCamera, contentDescription = null)
                }
            },
            modifier = Modifier
                .fillMaxWidth()
                .align(if (searchExpanded) Alignment.TopCenter else Alignment.BottomCenter)
                .padding(horizontal = 14.dp, vertical = if (searchExpanded) 0.dp else 14.dp),
        ) {
            SearchResultsContent(
                results = state.searchResults,
                isSearching = state.isSearching,
                onCustomerSelected = { customer ->
                    // Pass the search hit straight through — the old path
                    // re-parsed display name back into firstName/lastName via
                    // substringBefore/After which mangled compound surnames
                    // like 'Mc Donald'. attachFromSearchResult preserves the
                    // server-supplied fields verbatim.
                    viewModel.attachFromSearchResult(customer)
                    searchExpanded = false
                    // Don't auto-navigate — user just attached a customer;
                    // mockup PHONE 1 post-attach shows path picker first so
                    // the cashier can choose Retail / Repair / Store credit.
                    // (Walk-in still navigates straight to cart.)
                },
            )
        }
    }

    state.errorMessage?.let { msg ->
        LaunchedEffect(msg) {
            // Surface error to snackbar — host scaffold handles display
            viewModel.clearError()
        }
    }
}

// ─── Static content (path picker + hero + past repairs) ─────────────────────

@Composable
private fun EntryContent(
    state: PosEntryUiState,
    onRetailSale: () -> Unit,
    onRepairTicket: () -> Unit,
    onStoreCredit: () -> Unit,
    onOpenPickup: (Long) -> Unit,
    onWalkIn: () -> Unit,
) {
    if (state.attachedCustomer == null) {
        // Pre-attach: vertically center the 3 path tiles in the available
        // space between the top and the bottom search bar (mockup PHONE 1
        // uses flex 0.6 / 0.4 spacers around the tile column for the same
        // effect). RECENT strip pinned below the tiles.
        PreAttachContent(
            recentTickets = state.pastRepairs,
            onWalkIn = onWalkIn,
            onOpenTicket = { /* recent ticket tap — no-op pre-attach for now */ },
        )
    } else {
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 14.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
            contentPadding = PaddingValues(top = 24.dp, bottom = 120.dp),
        ) {
            // Post-attach state — customer is already attached
            item { CustomerHeaderBanner(customer = state.attachedCustomer!!) }

            item {
                PathTile(
                    emoji = "🛒",
                    title = "Retail sale",
                    subtitle = "Scan or browse parts · tender",
                    isPrimary = true,
                    onClick = onRetailSale,
                )
            }
            item {
                PathTile(
                    emoji = "🔧",
                    title = "Create repair ticket",
                    subtitle = "Pick device · describe · reserve parts",
                    isPrimary = false,
                    onClick = onRepairTicket,
                )
            }
            item {
                // Mockup PHONE 1 post-attach: subtitle reads
                // 'Balance: <green $X> · add funds'. When balance is zero
                // we fall back to 'Add funds' so the tile doesn't imply
                // there's money already loaded.
                val credit = state.attachedCustomer?.storeCreditCents ?: 0L
                val storeCreditSubtitle = if (credit > 0L) {
                    "Balance: ${credit.toDollarString()} · add funds"
                } else {
                    "Add funds"
                }
                PathTile(
                    emoji = "💳",
                    title = "Store credit · payment",
                    subtitle = storeCreditSubtitle,
                    isPrimary = false,
                    onClick = onStoreCredit,
                )
            }

            // Ready-for-pickup hero + past repairs — only meaningful once a
            // customer is attached.
            items(state.readyForPickupTickets) { ticket ->
                ReadyForPickupCard(ticket = ticket, onOpen = { onOpenPickup(ticket.ticketId) })
            }

            // Past repairs (or recent tickets if ready-for-pickup is empty).
            if (state.pastRepairs.isNotEmpty()) {
                item {
                    Text(
                        if (state.readyForPickupTickets.isEmpty()) "RECENT TICKETS" else "PAST REPAIRS",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(top = 4.dp, bottom = 4.dp),
                    )
                }
                items(state.pastRepairs) { repair ->
                    PastRepairRow(repair = repair)
                }
            }
        }
    }
}

// ─── Pre-attach content: vertically-centered tile column + RECENT strip ──

@Composable
private fun PreAttachContent(
    recentTickets: List<PastRepair>,
    onWalkIn: () -> Unit,
    onOpenTicket: (Long) -> Unit,
) {
    val viewModel: PosEntryViewModel = hiltViewModel()
    var showCreateDialog by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 14.dp)
            // Reserve room at the bottom for the docked SearchBar (~72dp + padding).
            .padding(bottom = 88.dp),
    ) {
        // Top spacer biases the tile column slightly above center (mockup
        // PHONE 1 uses 0.6/0.4 flex). Tiles render in middle band; RECENT
        // strip pinned below.
        Spacer(modifier = Modifier.weight(0.6f))

        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            PathTile(
                emoji = "👤",
                title = "Search customer",
                subtitle = "Tap or use search below",
                isPrimary = false,
                onClick = { /* search bar drives flow; tap is hint */ },
            )
            PathTile(
                emoji = "+",
                title = "Create new customer",
                subtitle = "First name required",
                isPrimary = true,
                onClick = { showCreateDialog = true },
            )
            GhostWalkInTile(onWalkIn = onWalkIn)
        }

        Spacer(modifier = Modifier.weight(0.4f))

        // RECENT chip strip — mockup PHONE 1 'RECENT' caption + chip row of
        // recent activity. Surfaces past tickets even pre-attach so cashier
        // can jump to a known sale.
        if (recentTickets.isNotEmpty()) {
            Text(
                "RECENT",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(bottom = 6.dp),
            )
            androidx.compose.foundation.lazy.LazyRow(
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                items(recentTickets, key = { it.ticketId }) { t ->
                    RecentTicketChip(repair = t, onClick = { onOpenTicket(t.ticketId) })
                }
            }
        }
    }

    if (showCreateDialog) {
        CreateCustomerDialog(
            onSubmit = { firstName, lastName, phone, email ->
                viewModel.createCustomerAndAttach(
                    firstName = firstName,
                    lastName = lastName.takeIf { it.isNotBlank() },
                    phone = phone.takeIf { it.isNotBlank() },
                    email = email.takeIf { it.isNotBlank() },
                )
                showCreateDialog = false
            },
            onDismiss = { showCreateDialog = false },
        )
    }
}

@Composable
private fun RecentTicketChip(repair: PastRepair, onClick: () -> Unit) {
    Surface(
        shape = RoundedCornerShape(99.dp),
        color = MaterialTheme.colorScheme.surfaceVariant,
        border = androidx.compose.foundation.BorderStroke(1.dp, MaterialTheme.colorScheme.outline),
        modifier = Modifier.clickable(onClickLabel = "Open ticket ${repair.ticketId}") { onClick() },
    ) {
        Text(
            "#${repair.ticketId} · ${repair.description.take(18)}",
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
            style = MaterialTheme.typography.labelMedium,
        )
    }
}

@Composable
private fun CreateCustomerDialog(
    onSubmit: (firstName: String, lastName: String, phone: String, email: String) -> Unit,
    onDismiss: () -> Unit,
) {
    var firstName by remember { mutableStateOf("") }
    var lastName by remember { mutableStateOf("") }
    var phone by remember { mutableStateOf("") }
    var email by remember { mutableStateOf("") }
    val canSubmit = firstName.isNotBlank()

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Create new customer") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedTextField(
                    value = firstName,
                    onValueChange = { firstName = it.take(80) },
                    label = { Text("First name *") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = lastName,
                    onValueChange = { lastName = it.take(80) },
                    label = { Text("Last name") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = phone,
                    onValueChange = { phone = it.take(40) },
                    label = { Text("Phone") },
                    singleLine = true,
                    keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(
                        keyboardType = androidx.compose.ui.text.input.KeyboardType.Phone,
                    ),
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = email,
                    onValueChange = { email = it.take(120) },
                    label = { Text("Email") },
                    singleLine = true,
                    keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(
                        keyboardType = androidx.compose.ui.text.input.KeyboardType.Email,
                    ),
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        },
        confirmButton = {
            TextButton(
                enabled = canSubmit,
                onClick = { onSubmit(firstName.trim(), lastName.trim(), phone.trim(), email.trim()) },
            ) { Text("Create") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

// ─── Reusable sub-composables ────────────────────────────────────────────────

@Composable
private fun CustomerHeaderBanner(customer: PosAttachedCustomer) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Box(
            modifier = Modifier
                .size(32.dp)
                .clip(CircleShape)
                .background(MaterialTheme.colorScheme.secondary),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                customer.name.split(" ").take(2).joinToString("") { it.take(1) }.uppercase(),
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onSecondary,
            )
        }
        Column(modifier = Modifier.weight(1f)) {
            Text(customer.name, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
            customer.phone?.let { ph ->
                Text("$ph · ${customer.ticketCount} tickets", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
private fun PathTile(
    emoji: String,
    title: String,
    subtitle: String,
    isPrimary: Boolean,
    onClick: () -> Unit,
) {
    val borderColor = if (isPrimary) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline
    val borderWidth = if (isPrimary) 1.5.dp else 1.dp

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .border(borderWidth, borderColor, RoundedCornerShape(14.dp))
            .background(MaterialTheme.colorScheme.surface)
            .clickable(onClickLabel = title) { onClick() }
            .padding(16.dp)
            .defaultMinSize(minHeight = 68.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        // M3 Expressive: primary tile uses MaterialShapes.Cookie9Sided for
        // its icon container so the alpha-shape morph is visible on the
        // brand-cream + tile (mockup uses plain rounded square; we lean into
        // expressive on the canonical primary action). Non-primary tiles
        // stay rounded to keep the row readable.
        @OptIn(ExperimentalMaterial3ExpressiveApi::class)
        val iconShape: androidx.compose.ui.graphics.Shape = if (isPrimary)
            MaterialShapes.Cookie9Sided.toShape()
        else RoundedCornerShape(11.dp)
        Box(
            modifier = Modifier
                .size(44.dp)
                .clip(iconShape)
                .background(if (isPrimary) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceVariant),
            contentAlignment = Alignment.Center,
        ) {
            // Mockup PHONE 1 pattern: primary tile fills the icon box with
            // cream so the glyph must paint in dark on-primary brown to stay
            // legible. Non-primary tiles keep the default emoji colors.
            Text(
                emoji,
                style = MaterialTheme.typography.titleLarge,
                fontWeight = if (isPrimary) FontWeight.Black else FontWeight.Normal,
                color = if (isPrimary) MaterialTheme.colorScheme.onPrimary else androidx.compose.ui.graphics.Color.Unspecified,
            )
        }
        Column(modifier = Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
            Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Text(
            "›",
            style = MaterialTheme.typography.titleMedium,
            color = if (isPrimary) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun GhostWalkInTile(onWalkIn: () -> Unit) {
    val dashed = MaterialTheme.colorScheme.outline
    val shape = RoundedCornerShape(14.dp)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .clickable(onClickLabel = "Walk-in customer") { onWalkIn() }
            .drawBehind {
                // Dashed outline via drawBehind + Stroke.dashPathEffect. No
                // Modifier.dashedBorder helper in Compose; inline avoids an
                // extra util file for a one-off.
                val strokeWidth = 1.5.dp.toPx()
                val dashEffect = PathEffect.dashPathEffect(
                    floatArrayOf(12f, 8f),
                    0f,
                )
                drawRoundRect(
                    color = dashed,
                    size = Size(size.width - strokeWidth, size.height - strokeWidth),
                    topLeft = androidx.compose.ui.geometry.Offset(strokeWidth / 2, strokeWidth / 2),
                    cornerRadius = CornerRadius(14.dp.toPx() - strokeWidth / 2),
                    style = Stroke(width = strokeWidth, pathEffect = dashEffect),
                )
            }
            .padding(horizontal = 16.dp, vertical = 14.dp)
            .defaultMinSize(minHeight = 60.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        // Ghost icon container: dashed square matches the tile's silhouette.
        Box(
            modifier = Modifier
                .size(44.dp)
                .drawBehind {
                    val strokeWidth = 1.5.dp.toPx()
                    val dashEffect = PathEffect.dashPathEffect(
                        floatArrayOf(8f, 6f),
                        0f,
                    )
                    drawRoundRect(
                        color = dashed,
                        size = Size(size.width - strokeWidth, size.height - strokeWidth),
                        topLeft = androidx.compose.ui.geometry.Offset(strokeWidth / 2, strokeWidth / 2),
                        cornerRadius = CornerRadius(12.dp.toPx()),
                        style = Stroke(width = strokeWidth, pathEffect = dashEffect),
                    )
                },
            contentAlignment = Alignment.Center,
        ) {
            Text(
                "👥",
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Column(modifier = Modifier.weight(1f)) {
            Text(
                "Walk-in customer",
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                "No customer record · quick sale",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Text("›", color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun ReadyForPickupCard(ticket: ReadyForPickupTicket, onOpen: () -> Unit) {
    // M3 Expressive: MaterialShapes.Cookie12Sided for the hero tile —
    // distinct brand silhouette that marks this row as the priority action.
    // Usability guardrail #5 is met: morph shape only on a brand surface
    // (not on content rows), not on list items.
    @OptIn(ExperimentalMaterial3ExpressiveApi::class)
    val heroShape = MaterialShapes.Cookie12Sided.toShape()
    val success = LocalExtendedColors.current.success
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(heroShape)
            .border(1.5.dp, success, heroShape)
            .background(success.copy(alpha = 0.08f))
            .clickable(onClickLabel = "Open ticket ${ticket.ticketId} cart") { onOpen() }
            .padding(horizontal = 18.dp, vertical = 14.dp)
            .defaultMinSize(minHeight = 60.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(
            modifier = Modifier
                .size(36.dp)
                .clip(RoundedCornerShape(10.dp))
                .background(success),
            contentAlignment = Alignment.Center,
        ) {
            Text("✓", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Black, color = androidx.compose.ui.graphics.Color(0xFF002817))
        }
        Column(modifier = Modifier.weight(1f)) {
            Text("#${ticket.ticketId} · Ready for pickup", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Bold)
            Text("${ticket.deviceName} · ${ticket.dueCents.toDollarString()} due", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Surface(
            shape = RoundedCornerShape(99.dp),
            color = success,
        ) {
            Text(
                "Open cart →",
                modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.Bold,
                color = androidx.compose.ui.graphics.Color(0xFF002817),
            )
        }
    }
}

@Composable
private fun PastRepairRow(repair: PastRepair) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = 44.dp)     // 44dp hit area
            .clickable(onClickLabel = "Open ticket ${repair.ticketId}") { /* navigate to ticket */ }
            .padding(horizontal = 10.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                "#${repair.ticketId}",
                style = MaterialTheme.typography.bodySmall,
                fontWeight = FontWeight.SemiBold,
                color = LocalExtendedColors.current.info,
            )
            Text("· ${repair.description}", style = MaterialTheme.typography.bodySmall)
        }
        Text(
            "${repair.date} · ${repair.amountCents.toDollarString()}",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

// ─── Search results ──────────────────────────────────────────────────────────

@Composable
private fun SearchResultsContent(
    results: SearchResultGroup,
    isSearching: Boolean,
    onCustomerSelected: (CustomerResult) -> Unit,
) {
    if (isSearching) {
        Box(modifier = Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) {
            // M3 Expressive LoadingIndicator morphs between shapes during short
            // (<5s) waits per Phase 4 guardrail. Replaces CircularProgressIndicator.
            @OptIn(ExperimentalMaterial3ExpressiveApi::class)
            LoadingIndicator(modifier = Modifier.size(40.dp))
        }
        return
    }

    LazyColumn(modifier = Modifier.fillMaxWidth()) {
        if (results.customers.isNotEmpty()) {
            item {
                Text(
                    "CUSTOMERS · ${results.customers.size}",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp),
                )
            }
            items(results.customers) { c ->
                CustomerResultRow(customer = c, onClick = { onCustomerSelected(c) })
            }
        }
        if (results.tickets.isNotEmpty()) {
            item {
                Text(
                    "TICKETS · ${results.tickets.size}",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp),
                )
            }
            items(results.tickets) { t ->
                TicketResultRow(ticket = t)
            }
        }
        if (results.customers.isEmpty() && results.tickets.isEmpty() && results.parts.isEmpty()) {
            item {
                Text(
                    "No results",
                    modifier = Modifier.padding(14.dp),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun CustomerResultRow(customer: CustomerResult, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClickLabel = "Select ${customer.name}") { onClick() }
            .padding(horizontal = 14.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Box(
            modifier = Modifier.size(32.dp).clip(CircleShape).background(MaterialTheme.colorScheme.secondary),
            contentAlignment = Alignment.Center,
        ) {
            Text(customer.initials, style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSecondary)
        }
        Column(modifier = Modifier.weight(1f)) {
            Text(customer.name, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
            Text(listOfNotNull(customer.phone, customer.email?.let { "${customer.ticketCount} tickets" }).joinToString(" · "), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
    HorizontalDivider()
}

@Composable
private fun TicketResultRow(ticket: TicketResult) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 14.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text("#${ticket.id} · ${ticket.customerName} · ${ticket.deviceName}", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
            Text(ticket.status, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
    HorizontalDivider()
}
