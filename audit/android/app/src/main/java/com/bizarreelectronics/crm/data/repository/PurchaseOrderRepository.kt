package com.bizarreelectronics.crm.data.repository

import android.util.Log
import com.bizarreelectronics.crm.data.remote.api.PurchaseOrderApi
import com.bizarreelectronics.crm.data.remote.dto.PurchaseOrderCreateRequest
import com.bizarreelectronics.crm.data.remote.dto.PurchaseOrderDetailData
import com.bizarreelectronics.crm.data.remote.dto.PurchaseOrderListData
import com.bizarreelectronics.crm.data.remote.dto.PurchaseOrderReceiveItemRequest
import com.bizarreelectronics.crm.data.remote.dto.PurchaseOrderReceiveRequest
import com.bizarreelectronics.crm.data.remote.dto.PurchaseOrderRow
import com.bizarreelectronics.crm.data.remote.dto.PurchaseOrderUpdateRequest
import com.bizarreelectronics.crm.data.remote.dto.SupplierRow
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class PurchaseOrderRepository @Inject constructor(
    private val api: PurchaseOrderApi,
) {

    // ── List ────────────────────────────────────────────────────────────────

    /**
     * Fetch a page of purchase orders, optionally filtered by [status].
     * Returns the [PurchaseOrderListData] directly from the server.
     */
    suspend fun listPurchaseOrders(
        page: Int = 1,
        pageSize: Int = 20,
        status: String? = null,
    ): PurchaseOrderListData {
        val response = api.listPurchaseOrders(page, pageSize, status)
        if (!response.success) throw RuntimeException(response.message ?: "Failed to load purchase orders")
        return response.data ?: PurchaseOrderListData(orders = emptyList())
    }

    // ── Create ──────────────────────────────────────────────────────────────

    /**
     * Create a new PO.  Returns the raw [PurchaseOrderRow] that was inserted.
     */
    suspend fun createPurchaseOrder(
        request: PurchaseOrderCreateRequest,
    ): PurchaseOrderRow {
        val response = api.createPurchaseOrder(request)
        if (!response.success) throw RuntimeException(response.message ?: "Failed to create purchase order")
        return response.data ?: throw RuntimeException("No data in create PO response")
    }

    // ── Detail ──────────────────────────────────────────────────────────────

    /** Fetch a single PO with its line items. */
    suspend fun getPurchaseOrder(id: Long): PurchaseOrderDetailData {
        val response = api.getPurchaseOrder(id)
        if (!response.success) throw RuntimeException(response.message ?: "Failed to load purchase order")
        return response.data ?: throw RuntimeException("No data in PO detail response")
    }

    // ── Receive ─────────────────────────────────────────────────────────────

    /**
     * Mark items as received, incrementing inventory quantities on the server.
     * [items] maps purchase_order_item_id → quantity_received.
     */
    suspend fun receivePurchaseOrder(
        id: Long,
        items: List<PurchaseOrderReceiveItemRequest>,
    ): PurchaseOrderRow {
        val request = PurchaseOrderReceiveRequest(items)
        val response = api.receivePurchaseOrder(id, request)
        if (!response.success) throw RuntimeException(response.message ?: "Failed to receive purchase order")
        return response.data ?: throw RuntimeException("No data in receive PO response")
    }

    // ── Update (status transitions) ─────────────────────────────────────────

    /**
     * Update PO status (e.g. to 'cancelled').  [cancelledReason] is included
     * when [status] == "cancelled".
     */
    suspend fun updatePurchaseOrder(
        id: Long,
        request: PurchaseOrderUpdateRequest,
    ): PurchaseOrderRow {
        val response = api.updatePurchaseOrder(id, request)
        if (!response.success) throw RuntimeException(response.message ?: "Failed to update purchase order")
        return response.data ?: throw RuntimeException("No data in update PO response")
    }

    // ── Suppliers ────────────────────────────────────────────────────────────

    /** Load the active-supplier list for the PO supplier picker. */
    suspend fun listSuppliers(): List<SupplierRow> {
        return try {
            val response = api.listSuppliers()
            if (response.success) response.data ?: emptyList()
            else emptyList()
        } catch (e: Exception) {
            Log.w(TAG, "listSuppliers failed: ${e.message}")
            emptyList()
        }
    }

    companion object {
        private const val TAG = "PurchaseOrderRepo"
    }
}
