package com.bizarreelectronics.crm.ui.screens.pos

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.db.dao.ParkedCartDao
import com.bizarreelectronics.crm.data.local.db.dao.SyncQueueDao
import com.bizarreelectronics.crm.data.local.db.entities.ParkedCartEntity
import com.bizarreelectronics.crm.data.local.db.entities.SyncQueueEntity
import com.bizarreelectronics.crm.data.remote.api.PosApi
import com.bizarreelectronics.crm.data.remote.api.QuickAddItem
import com.bizarreelectronics.crm.data.remote.dto.InventoryListItem
import com.bizarreelectronics.crm.util.NetworkMonitor
import com.google.gson.Gson
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.util.UUID
import javax.inject.Inject

// ─── Cart domain model ────────────────────────────────────────────────────────

data class CartLine(
    val id: String = UUID.randomUUID().toString(),
    val type: String = "inventory",   // "inventory" | "service" | "custom"
    val itemId: Long? = null,
    val name: String,
    val qty: Int = 1,
    val unitPriceCents: Long,
    val discountCents: Long = 0L,
    val taxClassId: Long? = null,
    val taxRate: Double = 0.0,       // 0.08 = 8%
    val photoUrl: String? = null,
) {
    val subtotalCents: Long get() = (unitPriceCents * qty) - discountCents
    val taxCents: Long get() = (subtotalCents * taxRate).toLong()
    val totalCents: Long get() = subtotalCents + taxCents
}

enum class DiscountMode { FLAT, PERCENT }

data class TipConfig(
    val enabled: Boolean = false,
    val mode: DiscountMode = DiscountMode.FLAT,
    val value: Long = 0L,            // cents if FLAT, basis points if PERCENT (500 = 5%)
)

data class AttachedCustomer(
    val id: Long,
    val name: String,
    val storeCreditCents: Long = 0L,
)

data class PosCartState(
    val lines: List<CartLine> = emptyList(),
    val cartDiscountCents: Long = 0L,
    val cartDiscountMode: DiscountMode = DiscountMode.FLAT,
    val tip: TipConfig = TipConfig(),
    val customer: AttachedCustomer? = null,
) {
    val subtotalCents: Long get() = lines.sumOf { it.subtotalCents }
    val taxCents: Long get() = lines.sumOf { it.taxCents }
    val discountCents: Long get() = when (cartDiscountMode) {
        DiscountMode.FLAT -> cartDiscountCents
        DiscountMode.PERCENT -> (subtotalCents * cartDiscountCents / 10000L)
    }
    val tipCents: Long get() = when (tip.mode) {
        DiscountMode.FLAT -> tip.value
        DiscountMode.PERCENT -> (subtotalCents * tip.value / 10000L)
    }
    val totalCents: Long get() = (subtotalCents + taxCents - discountCents + tipCents)
        .coerceAtLeast(0L)
    val lineCount: Int get() = lines.sumOf { it.qty }
}

// ─── Catalog / UI state ───────────────────────────────────────────────────────

data class PosUiState(
    // catalog
    val isLoadingCatalog: Boolean = false,
    val catalogItems: List<InventoryListItem> = emptyList(),
    val catalogSearch: String = "",
    val catalogCategory: String? = null,
    val catalogError: String? = null,
    val quickAddItems: List<QuickAddItem> = emptyList(),
    val quickAddVisible: Boolean = false,
    // cart
    val cart: PosCartState = PosCartState(),
    // parked
    val parkedCount: Int = 0,
    // payment
    val showPaymentSheet: Boolean = false,
    val isProcessing: Boolean = false,
    val paymentError: String? = null,
    val lastSaleInvoiceId: Long? = null,
    // offline
    val isOffline: Boolean = false,
    val pendingQueueCount: Int = 0,
    // success screen
    val showSuccessScreen: Boolean = false,
    // tab (phone only)
    val selectedTab: PosTab = PosTab.CATALOG,
)

enum class PosTab { CATALOG, CART }

// ─── ViewModel ────────────────────────────────────────────────────────────────

@OptIn(FlowPreview::class)
@HiltViewModel
class PosViewModel @Inject constructor(
    private val posApi: PosApi,
    private val parkedCartDao: ParkedCartDao,
    private val syncQueueDao: SyncQueueDao,
    private val networkMonitor: NetworkMonitor,
    private val gson: Gson,
) : ViewModel() {

    private val _state = MutableStateFlow(PosUiState())
    val state: StateFlow<PosUiState> = _state.asStateFlow()

    private val searchQuery = MutableStateFlow("")

    init {
        loadQuickAdd()
        observeParkedCount()
        observeSearchDebounced()
        observeOfflineState()
        observeSyncQueueCount()
    }

    // ── Catalog ──────────────────────────────────────────────────────────────

    private fun loadQuickAdd() {
        viewModelScope.launch {
            runCatching { posApi.getQuickAddItems() }
                .onSuccess { resp ->
                    if (resp.success && resp.data != null) {
                        _state.update {
                            it.copy(
                                quickAddItems = resp.data.items,
                                quickAddVisible = resp.data.items.isNotEmpty(),
                            )
                        }
                    }
                }
            // 404 or error → quickAddVisible stays false (silent)
        }
    }

    private fun observeSearchDebounced() {
        viewModelScope.launch {
            searchQuery
                .debounce(300)
                .distinctUntilChanged()
                .collect { query ->
                    _state.update { it.copy(catalogSearch = query) }
                    // Catalog items come from Room/local DB in real impl;
                    // here we just store the filter — PosCatalogGrid reads it.
                }
        }
    }

    fun onSearchChange(query: String) {
        searchQuery.value = query
    }

    fun onCategorySelect(category: String?) {
        _state.update { it.copy(catalogCategory = category) }
    }

    fun onBarcodeScanned(code: String) {
        // Lookup via inventory API — add to cart on match
        viewModelScope.launch {
            runCatching {
                // InventoryApi.lookupBarcode not directly injected here;
                // the barcode result bubbles up from PosCatalogGrid via a
                // callback. This stub is available for direct HID scanning.
            }
        }
    }

    // ── Cart mutations ───────────────────────────────────────────────────────

    fun addToCart(
        name: String,
        unitPriceCents: Long,
        itemId: Long? = null,
        type: String = "inventory",
        photoUrl: String? = null,
        taxRate: Double = 0.0,
        taxClassId: Long? = null,
    ) {
        _state.update { s ->
            val existing = s.cart.lines.indexOfFirst { it.itemId == itemId && itemId != null }
            val newLines = if (existing >= 0) {
                s.cart.lines.toMutableList().also { list ->
                    list[existing] = list[existing].copy(qty = list[existing].qty + 1)
                }
            } else {
                s.cart.lines + CartLine(
                    type = type,
                    itemId = itemId,
                    name = name,
                    unitPriceCents = unitPriceCents,
                    photoUrl = photoUrl,
                    taxRate = taxRate,
                    taxClassId = taxClassId,
                )
            }
            s.copy(cart = s.cart.copy(lines = newLines))
        }
    }

    fun setLineQty(lineId: String, qty: Int) {
        if (qty <= 0) {
            removeLine(lineId)
            return
        }
        _state.update { s ->
            s.copy(
                cart = s.cart.copy(
                    lines = s.cart.lines.map { if (it.id == lineId) it.copy(qty = qty) else it },
                )
            )
        }
    }

    fun setLineUnitPrice(lineId: String, priceCents: Long) {
        _state.update { s ->
            s.copy(
                cart = s.cart.copy(
                    lines = s.cart.lines.map {
                        if (it.id == lineId) it.copy(unitPriceCents = priceCents) else it
                    },
                )
            )
        }
    }

    fun setLineDiscount(lineId: String, discountCents: Long) {
        _state.update { s ->
            s.copy(
                cart = s.cart.copy(
                    lines = s.cart.lines.map {
                        if (it.id == lineId) it.copy(discountCents = discountCents) else it
                    },
                )
            )
        }
    }

    fun removeLine(lineId: String) {
        _state.update { s ->
            s.copy(cart = s.cart.copy(lines = s.cart.lines.filter { it.id != lineId }))
        }
    }

    fun setCartDiscount(cents: Long, mode: DiscountMode) {
        _state.update { s ->
            s.copy(cart = s.cart.copy(cartDiscountCents = cents, cartDiscountMode = mode))
        }
    }

    fun setTip(config: TipConfig) {
        _state.update { s -> s.copy(cart = s.cart.copy(tip = config)) }
    }

    fun attachCustomer(customer: AttachedCustomer?) {
        _state.update { s -> s.copy(cart = s.cart.copy(customer = customer)) }
    }

    fun clearCart() {
        _state.update { it.copy(cart = PosCartState()) }
    }

    // ── Tab (phone) ──────────────────────────────────────────────────────────

    fun selectTab(tab: PosTab) {
        _state.update { it.copy(selectedTab = tab) }
    }

    // ── Parked carts ─────────────────────────────────────────────────────────

    private fun observeParkedCount() {
        viewModelScope.launch {
            parkedCartDao.observeCount().collect { count ->
                _state.update { it.copy(parkedCount = count) }
            }
        }
    }

    fun parkCart(label: String? = null) {
        val cart = _state.value.cart
        if (cart.lines.isEmpty()) return
        val customer = cart.customer
        val displayLabel = label
            ?: customer?.name
            ?: "Cart ${System.currentTimeMillis() / 1000}"
        viewModelScope.launch {
            parkedCartDao.upsert(
                ParkedCartEntity(
                    id = UUID.randomUUID().toString(),
                    label = displayLabel,
                    cartJson = gson.toJson(cart),
                    customerId = customer?.id,
                    customerName = customer?.name,
                    subtotalCents = cart.subtotalCents,
                )
            )
            clearCart()
        }
    }

    fun resumeParkedCart(entity: ParkedCartEntity) {
        val cart = runCatching { gson.fromJson(entity.cartJson, PosCartState::class.java) }
            .getOrNull() ?: return
        _state.update { it.copy(cart = cart) }
        viewModelScope.launch { parkedCartDao.deleteById(entity.id) }
    }

    fun deleteParkedCart(entity: ParkedCartEntity) {
        viewModelScope.launch { parkedCartDao.deleteById(entity.id) }
    }

    // ── Payment sheet ────────────────────────────────────────────────────────

    fun showPaymentSheet() {
        _state.update { it.copy(showPaymentSheet = true) }
    }

    fun hidePaymentSheet() {
        _state.update { it.copy(showPaymentSheet = false, paymentError = null) }
    }

    fun clearPaymentError() {
        _state.update { it.copy(paymentError = null) }
    }

    // ── Offline state ────────────────────────────────────────────────────────

    private fun observeOfflineState() {
        viewModelScope.launch {
            networkMonitor.isOnline.collect { online ->
                _state.update { it.copy(isOffline = !online) }
            }
        }
    }

    private fun observeSyncQueueCount() {
        viewModelScope.launch {
            syncQueueDao.getCount().collect { count ->
                _state.update { it.copy(pendingQueueCount = count) }
            }
        }
    }

    /**
     * Queue a sale in sync_queue for offline / cash-only scenarios.
     * The drain-worker picks it up when connectivity is restored.
     */
    fun queueOfflineSale(cartJson: String, idempotencyKey: String) {
        viewModelScope.launch {
            runCatching {
                syncQueueDao.insert(
                    SyncQueueEntity(
                        entityType = "pos_sale",
                        entityId = 0L,
                        operation = "complete_sale",
                        payload = gson.toJson(
                            mapOf(
                                "idempotency_key" to idempotencyKey,
                                "cart" to cartJson,
                            )
                        ),
                    )
                )
            }
        }
    }

    // ── Success screen ───────────────────────────────────────────────────────

    fun dismissSuccessScreen() {
        _state.update { it.copy(showSuccessScreen = false, lastSaleInvoiceId = null) }
    }

    fun onSaleComplete(invoiceId: Long) {
        _state.update {
            it.copy(
                showPaymentSheet = false,
                isProcessing = false,
                lastSaleInvoiceId = invoiceId,
                showSuccessScreen = true,
                cart = PosCartState(),
            )
        }
    }

    fun onSaleError(message: String) {
        _state.update { it.copy(isProcessing = false, paymentError = message) }
    }

    fun setProcessing(processing: Boolean) {
        _state.update { it.copy(isProcessing = processing) }
    }
}
