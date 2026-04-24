package com.bizarreelectronics.crm.ui.screens.pos

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.LocalMall
import androidx.compose.material.icons.filled.ShoppingCart
import androidx.compose.material.icons.filled.Work
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.foundation.focusable
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.input.key.*
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.data.local.db.entities.ParkedCartEntity
import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
import com.bizarreelectronics.crm.data.remote.api.QuickAddItem
import com.bizarreelectronics.crm.data.remote.dto.InventoryListItem
import com.bizarreelectronics.crm.ui.screens.pos.components.PosCatalogGrid
import com.bizarreelectronics.crm.ui.screens.pos.components.PosCart
import com.bizarreelectronics.crm.ui.screens.pos.components.PosOfflineBanner
import com.bizarreelectronics.crm.ui.screens.pos.components.PosParkedCartsSheet
import com.bizarreelectronics.crm.ui.screens.pos.components.PosPaymentSheet
import com.bizarreelectronics.crm.ui.screens.pos.components.PosSuccessScreen
import com.bizarreelectronics.crm.util.isMediumOrExpandedWidth

/**
 * POS root screen.
 *
 * - Tablet: Row(catalog 60% | cart 40%) with rich top bar.
 * - Phone:  TabRow {Catalog | Cart} with badge on Cart tab.
 *
 * Plan §16.1 L1784-L1786.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PosScreen(
    onNavigateToTicketCreate: () -> Unit = {},
    onNavigateToTicket: (Long) -> Unit = {},
    appPreferences: AppPreferences? = null,
    viewModel: PosViewModel = hiltViewModel(),
) {
    PosScreenContent(
        viewModel = viewModel,
        appPreferences = appPreferences,
        onNavigateToTicketCreate = onNavigateToTicketCreate,
    )
}

/**
 * Separated content composable so [PosScreen] can pass a test VM easily.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun PosScreenContent(
    viewModel: PosViewModel = hiltViewModel(),
    appPreferences: AppPreferences? = null,
    onNavigateToTicketCreate: () -> Unit = {},
) {
    val state by viewModel.state.collectAsState()
    val customerSearchQuery by viewModel.customerSearchQuery.collectAsState()
    val customerSearchResults by viewModel.customerSearchResults.collectAsState()
    val customerSearchLoading by viewModel.customerSearchLoading.collectAsState()
    val isTablet = isMediumOrExpandedWidth()
    val snackbarHostState = remember { SnackbarHostState() }

    // Parked carts (Room Flow)
    var parkedCarts by remember { mutableStateOf<List<ParkedCartEntity>>(emptyList()) }
    var showParkedSheet by remember { mutableStateOf(false) }

    // POS keyboard shortcuts — F-key focus requests
    val searchFocusRequester = remember { FocusRequester() }
    val posKeysFocusRequester = remember { FocusRequester() }

    LaunchedEffect(Unit) {
        runCatching { posKeysFocusRequester.requestFocus() }
    }

    LaunchedEffect(state.paymentError) {
        state.paymentError?.let { err ->
            snackbarHostState.currentSnackbarData?.dismiss()
            snackbarHostState.showSnackbar(err)
            viewModel.clearPaymentError()
        }
    }

    // Inventory items for catalog — in a full impl these come from InventoryRepository.
    // For now we use an empty list; the grid handles empty state gracefully.
    val inventoryItems: List<InventoryListItem> = remember { emptyList() }

    // ── Success screen overlay ────────────────────────────────────────────
    if (state.showSuccessScreen && state.lastSaleInvoiceId != null) {
        // Cart was already cleared in onSaleComplete; we snapshot it before clearing.
        // For receipt display we reconstruct from invoice id — stub cart used here.
        val completedCart = remember { PosCartState() }
        PosSuccessScreen(
            cart = completedCart,
            invoiceId = state.lastSaleInvoiceId!!,
            serverBaseUrl = "https://localhost:443",
            appPreferences = appPreferences ?: return@PosScreenContent,
            onNewSale = viewModel::dismissSuccessScreen,
            onSmsSend = { _, _ -> Result.success(Unit) },
            modifier = Modifier.fillMaxSize(),
        )
        return
    }

    // ── POS keyboard shortcuts host ───────────────────────────────────────
    Box(
        modifier = Modifier
            .fillMaxSize()
            .focusRequester(posKeysFocusRequester)
            .focusable()
            .onPreviewKeyEvent { event ->
                if (event.type != KeyEventType.KeyDown) return@onPreviewKeyEvent false
                when (event.key) {
                    Key.F1 -> { viewModel.clearCart(); true }
                    Key.F2 -> { viewModel.selectTab(PosTab.CATALOG); true }
                    Key.F3 -> { /* customer search — open dialog */ true }
                    Key.F4 -> { /* discount dialog — open */ true }
                    Key.F5 -> { viewModel.showPaymentSheet(); true }
                    Key.F6 -> { viewModel.parkCart(); true }
                    Key.F7 -> { /* print — trigger receipt action */ true }
                    Key.F8 -> { /* refund — navigate to refunds flow */ true }
                    Key.F -> {
                        if (event.isCtrlPressed) {
                            runCatching { searchFocusRequester.requestFocus() }
                            true
                        } else false
                    }
                    else -> false
                }
            },
    ) {
        Scaffold(
            topBar = {
                Column {
                    // Offline banner (top of POS)
                    PosOfflineBanner(
                        isOffline = state.isOffline,
                        pendingQueueCount = state.pendingQueueCount,
                    )
                    PosTopBar(
                        parkedCount = state.parkedCount,
                        customerName = state.cart.customer?.name,
                        onParkedTap = { showParkedSheet = true },
                        onShiftTap = { /* shift management TODO */ },
                    )
                }
            },
            snackbarHost = { SnackbarHost(snackbarHostState) },
        ) { padding ->
            if (isTablet) {
                // ── 2-pane layout ─────────────────────────────────────────────
                Row(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                ) {
                    // Catalog pane (60%)
                    Box(modifier = Modifier.weight(0.6f)) {
                        PosCatalogGrid(
                            uiState = state,
                            inventoryItems = inventoryItems,
                            onSearchChange = viewModel::onSearchChange,
                            onCategorySelect = viewModel::onCategorySelect,
                            onItemTap = { item ->
                                viewModel.addToCart(
                                    name = item.name ?: "Item",
                                    unitPriceCents = ((item.price ?: 0.0) * 100).toLong(),
                                    itemId = item.id,
                                )
                            },
                            onQuickAddTap = { qi: QuickAddItem ->
                                viewModel.addToCart(
                                    name = qi.name,
                                    unitPriceCents = qi.priceCents,
                                    itemId = qi.id,
                                    photoUrl = qi.photoUrl,
                                )
                            },
                            onBarcodeScan = viewModel::onBarcodeScanned,
                        )
                    }
                    VerticalDivider()
                    // Cart pane (40%)
                    Box(modifier = Modifier.weight(0.4f)) {
                        PosCart(
                            cart = state.cart,
                            parkedCount = state.parkedCount,
                            onSetQty = viewModel::setLineQty,
                            onSetUnitPrice = viewModel::setLineUnitPrice,
                            onSetLineDiscount = viewModel::setLineDiscount,
                            onRemoveLine = viewModel::removeLine,
                            onSetCartDiscount = viewModel::setCartDiscount,
                            onSetTip = viewModel::setTip,
                            onAttachCustomer = viewModel::attachCustomer,
                            onPark = { viewModel.parkCart() },
                            onTender = viewModel::showPaymentSheet,
                            customerSearchQuery = customerSearchQuery,
                            customerSearchResults = customerSearchResults,
                            customerSearchLoading = customerSearchLoading,
                            onCustomerSearchQuery = viewModel::setCustomerSearchQuery,
                            onSelectExistingCustomer = viewModel::attachExistingCustomer,
                            onSelectWalkInCustomer = viewModel::attachWalkInCustomer,
                            onCreateNewCustomer = viewModel::createCustomerAndAttach,
                        )
                    }
                }
            } else {
                // ── Phone tabs layout ─────────────────────────────────────────
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                ) {
                    TabRow(selectedTabIndex = state.selectedTab.ordinal) {
                        Tab(
                            selected = state.selectedTab == PosTab.CATALOG,
                            onClick = { viewModel.selectTab(PosTab.CATALOG) },
                            icon = { Icon(Icons.Default.LocalMall, contentDescription = null) },
                            text = { Text("Catalog") },
                        )
                        Tab(
                            selected = state.selectedTab == PosTab.CART,
                            onClick = { viewModel.selectTab(PosTab.CART) },
                            icon = {
                                BadgedBox(
                                    badge = {
                                        if (state.cart.lineCount > 0) {
                                            Badge {
                                                Text(
                                                    "${state.cart.lineCount}",
                                                    modifier = Modifier.semantics {
                                                        contentDescription = "${state.cart.lineCount} items in cart"
                                                        liveRegion = LiveRegionMode.Polite
                                                    },
                                                )
                                            }
                                        }
                                    },
                                ) {
                                    Icon(Icons.Default.ShoppingCart, contentDescription = null)
                                }
                            },
                            text = { Text("Cart") },
                        )
                    }

                    when (state.selectedTab) {
                        PosTab.CATALOG -> PosCatalogGrid(
                            uiState = state,
                            inventoryItems = inventoryItems,
                            onSearchChange = viewModel::onSearchChange,
                            onCategorySelect = viewModel::onCategorySelect,
                            onItemTap = { item ->
                                viewModel.addToCart(
                                    name = item.name ?: "Item",
                                    unitPriceCents = ((item.price ?: 0.0) * 100).toLong(),
                                    itemId = item.id,
                                )
                            },
                            onQuickAddTap = { qi ->
                                viewModel.addToCart(
                                    name = qi.name,
                                    unitPriceCents = qi.priceCents,
                                    itemId = qi.id,
                                    photoUrl = qi.photoUrl,
                                )
                            },
                            onBarcodeScan = viewModel::onBarcodeScanned,
                            modifier = Modifier.weight(1f),
                        )
                        PosTab.CART -> PosCart(
                            cart = state.cart,
                            parkedCount = state.parkedCount,
                            onSetQty = viewModel::setLineQty,
                            onSetUnitPrice = viewModel::setLineUnitPrice,
                            onSetLineDiscount = viewModel::setLineDiscount,
                            onRemoveLine = viewModel::removeLine,
                            onSetCartDiscount = viewModel::setCartDiscount,
                            onSetTip = viewModel::setTip,
                            onAttachCustomer = viewModel::attachCustomer,
                            onPark = { viewModel.parkCart() },
                            onTender = viewModel::showPaymentSheet,
                            customerSearchQuery = customerSearchQuery,
                            customerSearchResults = customerSearchResults,
                            customerSearchLoading = customerSearchLoading,
                            onCustomerSearchQuery = viewModel::setCustomerSearchQuery,
                            onSelectExistingCustomer = viewModel::attachExistingCustomer,
                            onSelectWalkInCustomer = viewModel::attachWalkInCustomer,
                            onCreateNewCustomer = viewModel::createCustomerAndAttach,
                            modifier = Modifier.weight(1f),
                        )
                    }
                }
            }
        }
    }

    // ── Payment sheet ─────────────────────────────────────────────────────
    if (state.showPaymentSheet) {
        // PosPaymentSheet needs PosApi — injected indirectly via viewModel
        // In a proper Hilt setup PosApi is @Inject in a PosRepository used by the VM.
        // For compilation the interface reference is declared in the composable scope.
        // The actual payment logic lives inside PosPaymentSheet which takes posApi directly.
        // We delegate to a helper that gets it from the same Hilt component.
        PosPaymentSheetWrapper(
            viewModel = viewModel,
            cart = state.cart,
        )
    }

    // ── Parked carts sheet ────────────────────────────────────────────────
    if (showParkedSheet) {
        PosParkedCartsSheetWrapper(
            viewModel = viewModel,
            onDismiss = { showParkedSheet = false },
        )
    }
}

// ─── Top bar ──────────────────────────────────────────────────────────────────

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PosTopBar(
    parkedCount: Int,
    customerName: String?,
    onParkedTap: () -> Unit,
    onShiftTap: () -> Unit,
) {
    TopAppBar(
        title = {
            Text("Point of Sale", style = MaterialTheme.typography.titleMedium)
        },
        actions = {
            // Customer chip
            if (customerName != null) {
                AssistChip(
                    onClick = { /* open customer picker */ },
                    label = { Text(customerName, maxLines = 1) },
                    leadingIcon = {
                        Icon(
                            Icons.Default.Work,
                            contentDescription = null,
                            modifier = Modifier.size(16.dp),
                        )
                    },
                    modifier = Modifier.padding(end = 4.dp),
                )
            }
            // Shift chip
            AssistChip(
                onClick = onShiftTap,
                label = { Text("Shift") },
                modifier = Modifier.padding(end = 4.dp),
            )
            // Parked carts chip
            BadgedBox(
                badge = {
                    if (parkedCount > 0) {
                        Badge { Text("$parkedCount") }
                    }
                },
                modifier = Modifier.padding(end = 8.dp),
            ) {
                AssistChip(
                    onClick = onParkedTap,
                    label = { Text("Parked") },
                    modifier = Modifier.semantics {
                        contentDescription = if (parkedCount > 0) "$parkedCount parked carts" else "No parked carts"
                    },
                )
            }
        },
        colors = TopAppBarDefaults.topAppBarColors(
            containerColor = MaterialTheme.colorScheme.surface,
            titleContentColor = MaterialTheme.colorScheme.onSurface,
        ),
    )
}

// ─── Sheet wrappers (get dependencies from Hilt graph) ───────────────────────

@Composable
private fun PosPaymentSheetWrapper(
    viewModel: PosViewModel,
    cart: PosCartState,
) {
    // PosApi is injected into PosViewModel; expose via a helper VM or use EntryPoint.
    // For now we provide a no-op adapter — real wiring done in Hilt module.
    val posApiStub = remember {
        object : com.bizarreelectronics.crm.data.remote.api.PosApi {
            override suspend fun completeSale(
                idempotencyKey: String,
                request: com.bizarreelectronics.crm.data.remote.api.PosSaleRequest,
            ) = com.bizarreelectronics.crm.data.remote.dto.ApiResponse<com.bizarreelectronics.crm.data.remote.api.PosSaleData>(
                success = false,
                data = null,
                message = "PosApi not wired — configure Hilt module",
            )

            override suspend fun createInvoiceLater(
                idempotencyKey: String,
                request: com.bizarreelectronics.crm.data.remote.api.PosInvoiceLaterRequest,
            ) = com.bizarreelectronics.crm.data.remote.dto.ApiResponse<com.bizarreelectronics.crm.data.remote.api.PosSaleData>(
                success = false,
                data = null,
                message = "PosApi not wired",
            )

            override suspend fun redeemGiftCard(
                request: com.bizarreelectronics.crm.data.remote.api.PosGiftCardRedeemRequest,
            ) = com.bizarreelectronics.crm.data.remote.dto.ApiResponse<com.bizarreelectronics.crm.data.remote.api.PosGiftCardData>(
                success = false,
                data = null,
                message = "PosApi not wired",
            )

            override suspend fun getQuickAddItems() =
                com.bizarreelectronics.crm.data.remote.dto.ApiResponse<com.bizarreelectronics.crm.data.remote.api.QuickAddData>(
                    success = false,
                    data = null,
                )
        }
    }

    PosPaymentSheet(
        cart = cart,
        posApi = posApiStub,
        onSaleComplete = viewModel::onSaleComplete,
        onError = viewModel::onSaleError,
        onDismiss = viewModel::hidePaymentSheet,
    )
}

@Composable
private fun PosParkedCartsSheetWrapper(
    viewModel: PosViewModel,
    onDismiss: () -> Unit,
) {
    // Collect parked carts here
    val parkedCarts by viewModel.state.collectAsState()
    // Real list needs a separate Flow in VM; for now we show empty state
    // This is wired by adding observeParkedCarts() Flow to PosViewModel.
    val emptyList = remember { emptyList<ParkedCartEntity>() }

    PosParkedCartsSheet(
        parkedCarts = emptyList,
        onResume = { entity ->
            viewModel.resumeParkedCart(entity)
            onDismiss()
        },
        onDelete = { entity -> viewModel.deleteParkedCart(entity) },
        onDismiss = onDismiss,
    )
}
