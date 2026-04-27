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
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.input.key.utf16CodePoint
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.screens.pos.components.PosOfflineBanner
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
    onNavigateToTicket: (Long) -> Unit = {},
    onNavigateToStoreCreditPayment: () -> Unit = {},
    viewModel: PosEntryViewModel = hiltViewModel(),
    authPreferences: AuthPreferences? = null,
) {
    val state by viewModel.uiState.collectAsState()
    var searchExpanded by rememberSaveable { mutableStateOf(false) }
    val snackbarHostState = remember { SnackbarHostState() }
    val searchFocusRequester = remember { FocusRequester() }

    // ── HID barcode scanner buffer ────────────────────────────────────────────
    // HID scanners emit keystrokes extremely fast (< 50ms between chars).
    // Normal typing is slower. We detect HID vs human by measuring inter-key
    // gaps and accumulate a HID buffer; on Enter we submit it as a barcode
    // lookup rather than a text search.
    var hidBuffer by remember { mutableStateOf("") }
    var lastKeyMillis by remember { mutableLongStateOf(0L) }

    BackHandler(enabled = searchExpanded) { searchExpanded = false }

    PosKeyboardShortcuts(
        // F1 — new sale: collapse search bar and clear the search query so the
        // entry screen returns to its initial state. A full "detach customer +
        // clear cart" would go through PosCoordinator; at entry stage the
        // cheapest correct reset is to collapse the search overlay.
        onNewSale = { viewModel.onQueryChange(""); searchExpanded = false },
        // F2 — scan: no independent scan action on entry screen (scanner is
        // wired in PosCartScreen). No-op.
        onScan = {},
        // F3 / Ctrl+F — customer search: expand the SearchBar and focus it,
        // same as tapping the "Search customer" path tile.
        onCustomerSearch = {
            searchExpanded = true
            searchFocusRequester.requestFocus()
        },
        // F4 — discount: no cart yet at entry stage. No-op.
        onDiscount = {},
        // F5 — tender: no cart to tender from entry screen. No-op.
        onTender = {},
        // F6 — park: no cart to park at entry stage. No-op.
        onPark = {},
        // F7 — print: no receipt to print at entry stage. No-op.
        onPrint = {},
        // F8 — refund: refund flow not yet wired to PosEntry. No-op.
        onRefund = {},
        // Ctrl+F — same as F3: expand + focus customer SearchBar.
        onFocusSearch = {
            searchExpanded = true
            searchFocusRequester.requestFocus()
        },
    ) {
    // ── TopAppBar context values ──────────────────────────────────────────────
    val storePillLabel = remember(authPreferences) {
        val store = authPreferences?.storeName?.takeIf { it.isNotBlank() } ?: "Store #1"
        val user = authPreferences?.userFirstName?.takeIf { it.isNotBlank() }
            ?: authPreferences?.username?.takeIf { it.isNotBlank() }
        if (user != null) "$store · $user" else store
    }
    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        contentWindowInsets = WindowInsets(0),
        topBar = {
            BrandTopAppBar(
                title = "POS",
                actions = {
                    SuggestionChip(
                        onClick = { /* TODO: location / user picker */ },
                        label = {
                            Text(
                                storePillLabel,
                                style = MaterialTheme.typography.labelSmall,
                            )
                        },
                        modifier = Modifier.height(32.dp),
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                },
            )
        },
    ) { innerPadding ->
    // statusBarsPadding pushes the entire POS-entry surface below the
    // system status bar so the customer banner / clock no longer overlap.
    Box(modifier = Modifier.fillMaxSize().statusBarsPadding().padding(innerPadding)) {
        // TASK-4: offline banner defensive placement (top of entry screen)
        PosOfflineBanner(
            isOnline = state.isOnline,
            pendingSaleCount = state.pendingSaleCount,
            modifier = Modifier.align(Alignment.TopCenter).zIndex(1f),
        )
        // ── Content layer ───────────────────────────────────────────────────
        AnimatedVisibility(
            visible = !searchExpanded,
            enter = fadeIn(spring(stiffness = Spring.StiffnessMediumLow)),
            exit = fadeOut(spring(stiffness = Spring.StiffnessMediumLow)),
        ) {
            EntryContent(
                state = state,
                onRetailSale = onNavigateToCart,
                // Pass the attached customer's id verbatim (incl. id=0 for
                // walk-in). CheckInEntry's preFillCustomer treats id<=0 as a
                // walk-in marker and skips its Customer step so the cashier
                // doesn't pick the customer twice.
                onRepairTicket = { onNavigateToCheckin(state.attachedCustomer?.id) },
                onStoreCredit = onNavigateToStoreCreditPayment,
                onOpenPickup = { ticketId ->
                    // Mockup PHONE 1 'Open cart →' hero pill: skip the cart
                    // step entirely; the line is seeded by the VM and we
                    // jump straight to Tender so the cashier can charge.
                    viewModel.openReadyForPickup(ticketId)
                    onNavigateToTender()
                },
                onWalkIn = {
                    // Mockup PHONE 1 post-attach: walk-in still routes through
                    // the path picker (Retail / Repair / Store credit) so the
                    // cashier picks intent. Auto-nav to cart skipped that
                    // picker for walk-ins; restore parity with named-customer
                    // flow.
                    viewModel.attachWalkIn()
                },
                onNavigateToCart = onNavigateToCart,
                onNavigateToTicket = onNavigateToTicket,
                onSearchTap = {
                    searchExpanded = true
                    searchFocusRequester.requestFocus()
                },
                onCreateCustomer = { firstName, lastName, phone, email ->
                    viewModel.createCustomerAndAttach(
                        firstName = firstName,
                        lastName = lastName,
                        phone = phone,
                        email = email,
                    )
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
            placeholder = {
                Text("Customer, part, or ticket…")
            },
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
                .padding(horizontal = 14.dp, vertical = if (searchExpanded) 0.dp else 14.dp)
                .focusRequester(searchFocusRequester)
                .onPreviewKeyEvent { event ->
                    // HID scanner buffer: accumulate chars arriving < 50ms apart.
                    // On Enter (with a ≥ 6-char buffer), submit as barcode lookup.
                    if (event.type != KeyEventType.KeyDown) return@onPreviewKeyEvent false
                    val now = System.currentTimeMillis()
                    val gap = now - lastKeyMillis
                    lastKeyMillis = now
                    when {
                        event.key == Key.Enter || event.key == Key.NumPadEnter -> {
                            val buf = hidBuffer
                            hidBuffer = ""
                            if (buf.length >= 6) {
                                // HID-fast scan — treat as barcode, not text search
                                viewModel.lookupBarcode(buf)
                                true  // consume
                            } else false
                        }
                        gap < 50L -> {
                            // Fast keystroke — HID device
                            val char = event.utf16CodePoint.toChar()
                            if (char.isLetterOrDigit() || char in "-_/") {
                                hidBuffer += char
                            }
                            false  // let SearchBar also receive it
                        }
                        else -> {
                            // Slow keystroke — human typing; reset HID buffer
                            hidBuffer = ""
                            false
                        }
                    }
                },
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
                onOpenTicket = { id ->
                    searchExpanded = false
                    onNavigateToTicket(id)
                },
            )
        }
    }
    } // end Scaffold content lambda

    LaunchedEffect(state.errorMessage) {
        state.errorMessage?.let { msg ->
            snackbarHostState.showSnackbar(msg)
            viewModel.clearError()
        }
    }
    } // end PosKeyboardShortcuts
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
    onNavigateToCart: () -> Unit,
    onNavigateToTicket: (Long) -> Unit,
    onSearchTap: () -> Unit,
    onCreateCustomer: (firstName: String, lastName: String?, phone: String?, email: String?) -> Unit,
) {
    if (state.attachedCustomer == null) {
        // Pre-attach: vertically center the 3 path tiles in the available
        // space between the top and the bottom search bar (mockup PHONE 1
        // uses flex 0.6 / 0.4 spacers around the tile column for the same
        // effect). RECENT strip pinned below the tiles.
        PreAttachContent(
            recentTickets = state.pastRepairs,
            onWalkIn = onWalkIn,
            onOpenTicket = onNavigateToTicket,
            onSearchTap = onSearchTap,
            onCreateCustomer = onCreateCustomer,
        )
    } else {
        // Post-attach: header pinned top, 3 path tiles vertically biased to
        // upper-middle (mockup PHONE 1 0.6/0.4 spacers), Ready-for-pickup
        // hero + Past/Recent ticket list pinned bottom under the docked
        // search bar. Reachable + balanced.
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 14.dp)
                .padding(bottom = 88.dp),
        ) {
            CustomerHeaderBanner(customer = state.attachedCustomer!!)
            Spacer(modifier = Modifier.height(6.dp))
            // AUDIT-023: compact cart summary strip between the customer banner
            // and the path tiles. Tapping navigates to PosCart.
            CartSummaryStrip(
                lineCount = state.cartLineCount,
                subtotalCents = state.cartSubtotalCents,
                onClick = onNavigateToCart,
            )
            Spacer(modifier = Modifier.height(2.dp))

            Spacer(modifier = Modifier.weight(0.4f))

            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                PathTile(
                    emoji = "🛒",
                    title = "Retail sale",
                    subtitle = "Scan or browse parts · tender",
                    isPrimary = true,
                    onClick = onRetailSale,
                )
                PathTile(
                    emoji = "🔧",
                    title = "Create repair ticket",
                    subtitle = "Pick device · describe · reserve parts",
                    isPrimary = false,
                    onClick = onRepairTicket,
                )
                run {
                    val credit = state.attachedCustomer?.storeCreditCents ?: 0L
                    val storeCreditSubtitle = if (credit > 0L) {
                        "Balance: ${credit.toDollarString()} · add funds"
                    } else "Add funds"
                    PathTile(
                        emoji = "💳",
                        title = "Store credit · payment",
                        subtitle = storeCreditSubtitle,
                        isPrimary = false,
                        onClick = onStoreCredit,
                    )
                }
            }

            Spacer(modifier = Modifier.weight(0.6f))

            // Ready-for-pickup hero(s) + recent/past ticket list pinned at
            // the bottom of the column so they don't push the path tiles
            // off-screen and the cashier always sees recent activity for
            // this customer right above the docked search bar.
            if (state.readyForPickupTickets.isNotEmpty() || state.pastRepairs.isNotEmpty()) {
                LazyColumn(
                    modifier = Modifier.heightIn(max = 280.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    items(state.readyForPickupTickets) { ticket ->
                        ReadyForPickupCard(ticket = ticket, onOpen = { onOpenPickup(ticket.ticketId) })
                    }
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
                            PastRepairRow(repair = repair, onOpen = { onNavigateToTicket(repair.ticketId) })
                        }
                    }
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
    onSearchTap: () -> Unit,
    onCreateCustomer: (firstName: String, lastName: String?, phone: String?, email: String?) -> Unit,
) {
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
                onClick = onSearchTap,
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
                onCreateCustomer(
                    firstName,
                    lastName.takeIf { it.isNotBlank() },
                    phone.takeIf { it.isNotBlank() },
                    email.takeIf { it.isNotBlank() },
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

// ─── Cart summary strip (AUDIT-023) ─────────────────────────────────────────

/**
 * Compact one-line strip shown between CustomerHeaderBanner and the path tiles
 * in the post-attach state. Shows item count + subtotal (or "Cart · empty")
 * and navigates to PosCart on tap.
 */
@Composable
private fun CartSummaryStrip(
    lineCount: Int,
    subtotalCents: Long,
    onClick: () -> Unit,
) {
    val label = if (lineCount == 0) {
        "Cart · empty / \$0.00"
    } else {
        "Cart · $lineCount ${if (lineCount == 1) "item" else "items"} / ${subtotalCents.toDollarString()}"
    }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.6f))
            .clickable(onClickLabel = "Open cart") { onClick() }
            .padding(horizontal = 12.dp, vertical = 6.dp)
            .semantics(mergeDescendants = true) { contentDescription = label },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(
            label,
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            "›",
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun CustomerHeaderBanner(customer: PosAttachedCustomer) {
    val bannerDescription = buildString {
        append("Customer ${customer.name}")
        customer.phone?.let { append(", $it") }
        append(", ${customer.ticketCount} ${if (customer.ticketCount == 1) "ticket" else "tickets"}")
    }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .semantics(mergeDescendants = true) { contentDescription = bannerDescription },
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
    // AUDIT-031: replaced Cookie12Sided with plain RoundedCornerShape(12.dp).
    // Cookie12Sided clipped the border at its concave notches, creating a
    // "bitten cookie" silhouette and leaving tap-target gaps at each notch.
    val heroShape = RoundedCornerShape(12.dp)
    val success = LocalExtendedColors.current.success
    // AUDIT-039 + AUDIT-040: merged semantics so TalkBack reads the card as
    // one focusable, and Role.Button so it's announced as a button.
    val cardDescription = "Ready for pickup, Ticket #${ticket.ticketId}, ${ticket.deviceName}, ${ticket.dueCents.toDollarString()} due"
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(heroShape)
            .border(1.5.dp, success, heroShape)
            .background(success.copy(alpha = 0.08f))
            .clickable(onClickLabel = "Open ticket ${ticket.ticketId} cart") { onOpen() }
            .padding(horizontal = 18.dp, vertical = 14.dp)
            .defaultMinSize(minHeight = 60.dp)
            .semantics(mergeDescendants = true) {
                contentDescription = cardDescription
                role = Role.Button
            },
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
private fun PastRepairRow(repair: PastRepair, onOpen: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = 44.dp)     // 44dp hit area
            .clickable(onClickLabel = "Open ticket ${repair.ticketId}") { onOpen() }
            .padding(horizontal = 10.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        // AUDIT-038: bumped from bodySmall (12sp, ~4.1:1 on onSurfaceVariant) to
        // bodyMedium (14sp) which clears AA-medium (3:1). The ticket-id accent
        // color (info) is on a surface background and passes at 14sp.
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                "#${repair.ticketId}",
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold,
                color = LocalExtendedColors.current.info,
            )
            Text("· ${repair.description}", style = MaterialTheme.typography.bodyMedium)
        }
        Text(
            "${repair.date} · ${repair.amountCents.toDollarString()}",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurface,
        )
    }
}

// ─── Search results ──────────────────────────────────────────────────────────

@Composable
private fun SearchResultsContent(
    results: SearchResultGroup,
    isSearching: Boolean,
    onCustomerSelected: (CustomerResult) -> Unit,
    onOpenTicket: (Long) -> Unit,
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
                TicketResultRow(ticket = t, onClick = { onOpenTicket(t.id) })
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
            Text(
                listOfNotNull(
                    customer.phone,
                    customer.email,
                    if (customer.ticketCount > 0) "${customer.ticketCount} tickets" else null,
                ).joinToString(" · "),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
    HorizontalDivider()
}

@Composable
private fun TicketResultRow(ticket: TicketResult, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClickLabel = "Open ticket ${ticket.id}") { onClick() }
            .semantics { role = Role.Button }
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
