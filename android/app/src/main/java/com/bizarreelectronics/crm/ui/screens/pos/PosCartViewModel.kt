package com.bizarreelectronics.crm.ui.screens.pos

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.db.dao.ParkedCartDao
import com.bizarreelectronics.crm.data.local.db.dao.SyncQueueDao
import com.bizarreelectronics.crm.data.local.db.entities.SyncQueueEntity
import com.bizarreelectronics.crm.data.remote.api.InventoryApi
import com.bizarreelectronics.crm.data.remote.api.PosApi
import com.bizarreelectronics.crm.data.remote.api.QuickAddItem
import com.bizarreelectronics.crm.ui.screens.pos.components.JurisdictionRule
import com.bizarreelectronics.crm.ui.screens.pos.components.PosTaxCalculator
import com.bizarreelectronics.crm.ui.screens.pos.components.TaxBreakdown
import com.bizarreelectronics.crm.ui.screens.pos.components.TenantTaxConfig
import com.bizarreelectronics.crm.util.NetworkMonitor
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.util.UUID
import javax.inject.Inject

data class PosCartUiState(
    val customer: PosAttachedCustomer? = null,
    val lines: List<CartLine> = emptyList(),
    val cartDiscountCents: Long = 0L,
    val cartNote: String? = null,
    val editingLineId: String? = null,
    val taxRate: Double = 0.0,
    val scanMessage: String? = null,
    /** Linked repair-ticket draft id — drives the "Ticket draft" topbar subtitle */
    val linkedTicketId: Long? = null,
    /** Quick-add catalog tiles populated from /pos-enrich/quick-add (Today's Top-5 + fallback). */
    val catalog: List<QuickAddItem> = emptyList(),
    // ── TopAppBar chip state ──────────────────────────────────────────────────
    /** Location display name. TODO: fetch from server settings. */
    val locationName: String = "Main Store",
    /** Whether a shift is currently active. TODO: wire to actual clock-in API. */
    val shiftActive: Boolean = true,
    /** Count of locally parked carts. Sourced from ParkedCartDao.observeCount(). */
    val parkedCartCount: Int = 0,
    // ── TASK-1: tip ──────────────────────────────────────────────────────────
    val tipCents: Long = 0L,
    // ── TASK-4: offline banner ────────────────────────────────────────────────
    val isOnline: Boolean = true,
    /** Count of queued pos_sale entries awaiting sync. */
    val pendingSaleCount: Int = 0,
    // ── TASK-5: tax breakdown ─────────────────────────────────────────────────
    val taxBreakdown: TaxBreakdown? = null,
) {
    val subtotalCents: Long get() = lines.sumOf { it.lineTotalCents }
    val taxCents: Long get() = taxBreakdown?.totalTaxCents ?: lines.sumOf { it.taxCents }
    val discountCents: Long get() = cartDiscountCents
    // TASK-1: mirror coordinator totalCents formula (includes tip)
    val totalCents: Long get() = (subtotalCents + taxCents - cartDiscountCents + tipCents).coerceAtLeast(0L)

    val editingLine: CartLine? get() = lines.firstOrNull { it.id == editingLineId }
}

@HiltViewModel
class PosCartViewModel @Inject constructor(
    private val coordinator: PosCoordinator,
    private val inventoryApi: InventoryApi,
    private val posApi: PosApi,
    private val parkedCartDao: ParkedCartDao,
    private val syncQueueDao: SyncQueueDao,
    private val networkMonitor: NetworkMonitor,
) : ViewModel() {

    private val gson = Gson()

    private val _uiState = MutableStateFlow(PosCartUiState())
    val uiState: StateFlow<PosCartUiState> = _uiState.asStateFlow()

    /** Live list of parked carts for [PosParkedCartsSheet]. */
    val parkedCarts = parkedCartDao.observeAll()

    init {
        // Mirror coordinator session into local UI state
        viewModelScope.launch {
            coordinator.session.collect { session ->
                val breakdown = computeTaxBreakdown(session.lines, _uiState.value.taxRate)
                _uiState.update {
                    it.copy(
                        customer = session.customer,
                        lines = session.lines,
                        cartDiscountCents = session.cartDiscountCents,
                        cartNote = session.cartNote,
                        linkedTicketId = session.linkedTicketId,
                        tipCents = session.tipCents,
                        taxBreakdown = breakdown,
                    )
                }
            }
        }
        // TASK-4: observe network state
        viewModelScope.launch {
            networkMonitor.isOnline.collect { online ->
                _uiState.update { it.copy(isOnline = online) }
            }
        }
        // TASK-4: observe pending pos_sale count from sync queue
        viewModelScope.launch {
            syncQueueDao.getCount().collect { _ ->
                // getCount() tracks all pending; query for pos_sale specifically
                val count = syncQueueDao.countPendingByOpType("pos_sale")
                _uiState.update { it.copy(pendingSaleCount = count) }
            }
        }
        // POS-TAX-001: load the default tax class rate from
        // /api/v1/settings/tax-classes so cart totals show real tax (mockup
        // PHONE 3 'Tax · 8.5%'). Falls back to 0.0 on a missing default
        // row so the cart still renders without a tax line in dev DBs.
        viewModelScope.launch {
            runCatching { inventoryApi.getTaxClasses() }
                .onSuccess { resp ->
                    val classes = resp.data.orEmpty()
                    // tax_classes.rate is stored as a PERCENT (e.g. 8.5 for
                    // 8.5%) on the server (matches invoices.routes.ts +
                    // pos.routes.ts /transaction which divide by 100 when
                    // multiplying line nets). Convert to a fraction here so
                    // CartLine.taxCents = lineTotalCents * taxRate gives
                    // sensible cents instead of 886%-of-subtotal totals.
                    val ratePercent = classes.firstOrNull { it.isDefault == 1 }?.rate
                        ?: classes.firstOrNull()?.rate
                        ?: 0.0
                    val taxFraction = ratePercent / 100.0
                    _uiState.update { state ->
                        state.copy(
                            taxRate = taxFraction,
                            taxBreakdown = computeTaxBreakdown(state.lines, taxFraction),
                        )
                    }
                }
        }
        // Mockup PHONE 3 'Catalog' tab — fetch quick-add tiles. Server route
        // returns Today's Top-5 sold items + fallback to first 10 active when
        // there are no sales yet today. Errors silently ignored — Catalog
        // tab simply renders empty state.
        viewModelScope.launch {
            runCatching { posApi.getQuickAddItems() }
                .onSuccess { resp ->
                    val items = resp.data?.items.orEmpty()
                    _uiState.update { it.copy(catalog = items) }
                }
        }
        // Mirror parked-cart count into UI state so the TopAppBar chip appears
        // automatically whenever a cart is parked and disappears when restored.
        viewModelScope.launch {
            parkedCartDao.observeCount().collect { count ->
                _uiState.update { it.copy(parkedCartCount = count) }
            }
        }
    }

    /** Tap on a Catalog tile → add inventory line. */
    fun addQuickAddItem(item: QuickAddItem) {
        addInventoryItem(
            itemId = item.id,
            name = item.name,
            unitPriceCents = item.priceCents,
            sku = item.sku,
        )
    }

    fun addMiscItem(name: String, unitPriceCents: Long) {
        val line = CartLine(
            type = "custom",
            name = name,
            unitPriceCents = unitPriceCents,
            taxRate = _uiState.value.taxRate,
        )
        pushLines(_uiState.value.lines + line)
    }

    fun addInventoryItem(
        itemId: Long,
        name: String,
        unitPriceCents: Long,
        sku: String? = null,
        taxRate: Double? = null,
    ) {
        // Use the per-item tax rate if the caller supplied one (e.g. an
        // inventory item with a non-default tax class); otherwise inherit the
        // cart's loaded default rate so the totals row picks up real tax math.
        val effectiveRate = taxRate ?: _uiState.value.taxRate
        val existing = _uiState.value.lines.indexOfFirst { it.itemId == itemId && it.type == "inventory" }
        val updated = if (existing >= 0) {
            _uiState.value.lines.mapIndexed { i, l ->
                if (i == existing) l.copy(qty = l.qty + 1) else l
            }
        } else {
            _uiState.value.lines + CartLine(
                type = "inventory",
                itemId = itemId,
                name = name,
                sku = sku,
                unitPriceCents = unitPriceCents,
                taxRate = effectiveRate,
            )
        }
        pushLines(updated)
    }

    /** Called when BarcodeAnalyzer resolves a barcode to an inventory item. */
    fun onBarcodeResolved(itemId: Long, name: String, priceCents: Long, sku: String? = null) =
        addInventoryItem(itemId, name, priceCents, sku = sku)

    /**
     * Look up a scanned barcode / SKU against `/inventory/barcode/{code}`
     * and add the resolved item to the cart. Surfaces a scanMessage
     * either way so the cart screen can flash a snackbar with the
     * result ("Added: iPhone 14 Pro Screen" or "No item for code 123").
     */
    fun scanBarcode(code: String) {
        val trimmed = code.trim()
        if (trimmed.isBlank()) return
        viewModelScope.launch {
            runCatching { inventoryApi.lookupBarcode(trimmed) }
                .onSuccess { resp ->
                    val item = resp.data?.item
                    if (item == null) {
                        _uiState.update { it.copy(scanMessage = "No item for code $trimmed") }
                        return@onSuccess
                    }
                    val priceCents = Math.round((item.price ?: 0.0) * 100)
                    addInventoryItem(
                        itemId = item.id,
                        name = item.name ?: "Item #${item.id}",
                        unitPriceCents = priceCents,
                        sku = item.sku,
                    )
                    _uiState.update { it.copy(scanMessage = "Added: ${item.name ?: "item"}") }
                }
                .onFailure { e ->
                    _uiState.update {
                        it.copy(scanMessage = "Scan lookup failed: ${e.message ?: "network error"}")
                    }
                }
        }
    }

    fun clearScanMessage() = _uiState.update { it.copy(scanMessage = null) }

    fun setLineQty(lineId: String, qty: Int) {
        if (qty < 1) return
        val updated = _uiState.value.lines.map { if (it.id == lineId) it.copy(qty = qty.coerceIn(1, 999)) else it }
        pushLines(updated)
    }

    fun setLineDiscount(lineId: String, discountCents: Long) {
        val updated = _uiState.value.lines.map { if (it.id == lineId) it.copy(discountCents = discountCents) else it }
        pushLines(updated)
    }

    fun setLineNote(lineId: String, note: String) {
        val updated = _uiState.value.lines.map { if (it.id == lineId) it.copy(note = note.take(1000)) else it }
        pushLines(updated)
    }

    fun removeLine(lineId: String) {
        pushLines(_uiState.value.lines.filter { it.id != lineId })
        if (_uiState.value.editingLineId == lineId) dismissLineEdit()
    }

    fun setCartDiscount(cents: Long) {
        coordinator.setCartDiscount(cents)
    }

    fun setCartNote(note: String) {
        coordinator.setCartNote(note.take(1000))
    }

    fun detachCustomer() = coordinator.detachCustomer()

    fun openLineEdit(lineId: String) = _uiState.update { it.copy(editingLineId = lineId) }

    fun dismissLineEdit() = _uiState.update { it.copy(editingLineId = null) }

    // ── TASK-1: tip ───────────────────────────────────────────────────────────

    /** Set the cart tip. Delegates to coordinator so PosTender sees the updated totalCents. */
    fun setTip(cents: Long) {
        coordinator.setTip(cents)
    }

    // ── TASK-2: parked cart full restore (POS-PARK-002) ───────────────────────

    /**
     * Restore a parked cart by id. Parses the stored cartJson back into
     * coordinator state (lines + customer + cartDiscount + linkedTicketId),
     * then deletes the parked row so the chip count decrements.
     */
    fun restoreParkedCart(cartId: String) {
        viewModelScope.launch {
            val entity = parkedCartDao.getById(cartId) ?: return@launch
            var restoredLineCount = 0
            runCatching {
                val type = object : TypeToken<ParkedCartSnapshot>() {}.type
                val snapshot = gson.fromJson<ParkedCartSnapshot>(entity.cartJson, type)
                restoredLineCount = snapshot.lines.size
                coordinator.resetSession()
                coordinator.setLines(snapshot.lines)
                coordinator.setCartDiscount(snapshot.cartDiscountCents)
                snapshot.cartNote?.let { coordinator.setCartNote(it) }
                snapshot.linkedTicketId?.let { coordinator.setLinkedTicket(it) }
                snapshot.customer?.let { c ->
                    coordinator.attachCustomer(
                        PosAttachedCustomer(
                            id = c.id,
                            name = c.name,
                            phone = c.phone,
                            email = c.email,
                            storeCreditCents = c.storeCreditCents,
                            taxExempt = c.taxExempt,
                        )
                    )
                }
            }
            parkedCartDao.deleteById(cartId)
            // Surface "Cart restored" snackbar via the scan-message channel
            if (restoredLineCount > 0) {
                _uiState.update { it.copy(scanMessage = "Cart restored — $restoredLineCount item(s)") }
            }
        }
    }

    /**
     * T-C10 — hydrate cart from a ticket id (Checkout deep link from
     * tablet ticket detail). Sets the linked ticket so existing tender
     * flows pick it up; full line-population from /tickets/:id is
     * server-wiring deferred per TODO.md (T-C10 follow-up).
     */
    fun hydrateFromTicket(ticketId: Long) {
        viewModelScope.launch {
            coordinator.setLinkedTicket(ticketId)
            _uiState.update { it.copy(scanMessage = "Linked to ticket #$ticketId — add lines to checkout") }
        }
    }

    // ── TASK-3: unit-price override ───────────────────────────────────────────

    /**
     * Override a line's unit price (admin/manager only — enforced by caller).
     * Stamps [CartLine.originalUnitPriceCents] for strikethrough hint when price
     * differs from the original. Also enqueues a price_override audit entry.
     *
     * @param reason Mandatory reason text supplied alongside the override. Used
     *   as the SyncQueue payload comment (price_override audit).
     */
    fun setLineUnitPrice(lineId: String, newPriceCents: Long, reason: String = "") {
        val updated = _uiState.value.lines.map { line ->
            if (line.id != lineId) line
            else line.copy(
                unitPriceCents = newPriceCents,
                originalUnitPriceCents = if (newPriceCents != line.unitPriceCents)
                    line.originalUnitPriceCents ?: line.unitPriceCents
                else line.originalUnitPriceCents,
            )
        }
        pushLines(updated)
        // Audit: queue price_override for sync
        viewModelScope.launch {
            val payload = gson.toJson(
                mapOf(
                    "line_id" to lineId,
                    "new_price_cents" to newPriceCents,
                    "reason" to reason,
                )
            )
            syncQueueDao.insert(
                SyncQueueEntity(
                    entityType = "cart_line",
                    entityId = 0L,
                    operation = "price_override",
                    payload = payload,
                    idempotencyKey = UUID.randomUUID().toString(),
                )
            )
        }
    }

    // ── TASK-5: tax breakdown computation ────────────────────────────────────

    /**
     * Build a [TaxBreakdown] from current lines + rate using [PosTaxCalculator].
     * Uses a single flat jurisdiction ("default") built from the loaded tax rate.
     * TODO: replace with TenantSettingsRepository that supplies real multi-jurisdiction config.
     */
    private fun computeTaxBreakdown(lines: List<CartLine>, taxFraction: Double): TaxBreakdown? {
        if (taxFraction <= 0.0 || lines.isEmpty()) return null
        val rateBps = (taxFraction * 10_000).toInt()
        val config = TenantTaxConfig(
            jurisdictions = listOf(
                JurisdictionRule(
                    jurisdictionId = "default",
                    name = "Tax · ${"%.2f".format(taxFraction * 100).trimEnd('0').trimEnd('.')}%",
                    rateBps = rateBps,
                )
            ),
        )
        val cartState = PosCartState(
            lines = lines,
            customer = _uiState.value.customer?.let {
                AttachedCustomer(id = it.id, name = it.name, taxExempt = it.taxExempt)
            },
        )
        return PosTaxCalculator.calculate(cartState, config)
    }

    private fun pushLines(lines: List<CartLine>) {
        coordinator.setLines(lines)
    }
}

/**
 * Minimal snapshot stored in [com.bizarreelectronics.crm.data.local.db.entities.ParkedCartEntity.cartJson].
 * Mirrors the fields we serialize at park time (see PosTenderViewModel.parkCart).
 */
data class ParkedCartSnapshot(
    val lines: List<CartLine> = emptyList(),
    val cartDiscountCents: Long = 0L,
    val cartNote: String? = null,
    val linkedTicketId: Long? = null,
    val customer: ParkedCustomerSnapshot? = null,
)

data class ParkedCustomerSnapshot(
    val id: Long,
    val name: String,
    val phone: String? = null,
    val email: String? = null,
    val storeCreditCents: Long = 0L,
    val taxExempt: Boolean = false,
)
