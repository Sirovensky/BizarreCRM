package com.bizarreelectronics.crm.data.repository

import android.util.Log
import com.bizarreelectronics.crm.data.local.db.dao.TicketDao
import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.remote.api.CashTrappedData
import com.bizarreelectronics.crm.data.remote.api.ReportApi
import com.bizarreelectronics.crm.data.remote.api.TicketApi
import com.bizarreelectronics.crm.data.remote.dto.ChurnRiskCustomer
import com.bizarreelectronics.crm.data.remote.dto.TicketListItem
import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
import kotlinx.coroutines.flow.Flow
import retrofit2.HttpException
import javax.inject.Inject
import javax.inject.Singleton

data class DashboardStats(
    val openTickets: Int = 0,
    val revenueToday: Double = 0.0,
    val appointmentsToday: Int = 0,
    val ticketsDueToday: Int = 0,
    val isFromCache: Boolean = false,
)

data class NeedsAttention(
    val lowStockCount: Int = 0,
    val missingPartsCount: Int = 0,
    val staleTicketsCount: Int = 0,
    val overdueInvoicesCount: Int = 0,
    val isFromCache: Boolean = false,
)

@Singleton
class DashboardRepository @Inject constructor(
    private val ticketDao: TicketDao,
    private val ticketApi: TicketApi,
    private val reportApi: ReportApi,
    private val authPreferences: AuthPreferences,
    private val appPreferences: AppPreferences,
    private val serverMonitor: ServerReachabilityMonitor,
) {
    /** Fetch dashboard KPIs. Falls back to cached values when offline. */
    suspend fun getDashboardStats(): DashboardStats {
        if (serverMonitor.isEffectivelyOnline.value) {
            try {
                val response = reportApi.getDashboard()
                val data = response.data ?: return cachedStats()
                val stats = DashboardStats(
                    openTickets = (data["open_tickets"] as? Number)?.toInt() ?: 0,
                    revenueToday = (data["revenue_today"] as? Number)?.toDouble() ?: 0.0,
                    appointmentsToday = (data["appointments_today"] as? Number)?.toInt() ?: 0,
                    ticketsDueToday = (data["tickets_due_today"] as? Number)?.toInt() ?: 0,
                )
                // Cache for offline use
                appPreferences.cachedOpenTickets = stats.openTickets
                appPreferences.cachedRevenueToday = stats.revenueToday
                return stats
            } catch (e: Exception) {
                Log.w(TAG, "Dashboard API failed: ${e.message}")
            }
        }
        return cachedStats()
    }

    /** Fetch needs-attention data. Falls back to cached when offline. */
    suspend fun getNeedsAttention(): NeedsAttention {
        if (serverMonitor.isEffectivelyOnline.value) {
            try {
                val response = reportApi.getNeedsAttention()
                val data = response.data ?: return cachedAttention()
                val attention = NeedsAttention(
                    lowStockCount = (data["low_stock_count"] as? Number)?.toInt() ?: 0,
                    missingPartsCount = (data["missing_parts_count"] as? Number)?.toInt() ?: 0,
                    staleTicketsCount = (data["stale_tickets_count"] as? Number)?.toInt() ?: 0,
                    overdueInvoicesCount = (data["overdue_invoices_count"] as? Number)?.toInt() ?: 0,
                )
                // Cache for offline use
                appPreferences.cachedLowStock = attention.lowStockCount
                appPreferences.cachedMissingParts = attention.missingPartsCount
                appPreferences.cachedStaleTickets = attention.staleTicketsCount
                appPreferences.cachedOverdueInvoices = attention.overdueInvoicesCount
                return attention
            } catch (e: Exception) {
                Log.w(TAG, "NeedsAttention API failed: ${e.message}")
            }
        }
        return cachedAttention()
    }

    /** My Queue — user's assigned open tickets. Returns Room Flow. */
    fun getMyQueue(): Flow<List<com.bizarreelectronics.crm.data.local.db.entities.TicketEntity>> {
        return ticketDao.getByAssignedTo(authPreferences.userId)
    }

    /** Fetch My Queue from API and cache into Room. */
    suspend fun refreshMyQueue(): List<TicketListItem> {
        if (!serverMonitor.isEffectivelyOnline.value) return emptyList()
        return try {
            val userId = authPreferences.userId
            val response = ticketApi.getTickets(
                mapOf("assigned_to" to userId.toString(), "is_open" to "1", "pagesize" to "50")
            )
            val tickets = response.data?.tickets ?: emptyList()
            ticketDao.insertAll(tickets.map { it.toEntity() })
            tickets
        } catch (e: Exception) {
            Log.w(TAG, "My Queue refresh failed: ${e.message}")
            emptyList()
        }
    }

    /**
     * §45.3 — Fetch churn-risk customer list from GET /reports/churn-risk.
     *
     * Returns Pair(count, customers). On 404 (endpoint not yet live) returns (null, empty)
     * so the Dashboard ChurnAlertCard shows "Data unavailable" rather than crashing.
     */
    suspend fun getChurnRisk(): Pair<Int?, List<ChurnRiskCustomer>> {
        if (!serverMonitor.isEffectivelyOnline.value) return Pair(null, emptyList())
        return try {
            val response = reportApi.getChurnRisk()
            val data = response.data ?: return Pair(null, emptyList())
            Pair(data.atRiskCount, data.customers)
        } catch (e: HttpException) {
            if (e.code() == 404) {
                // Endpoint not yet live — ChurnAlertCard degrades gracefully.
                Log.d(TAG, "churn-risk endpoint 404 — ChurnAlertCard shows unavailable")
            } else {
                Log.w(TAG, "getChurnRisk failed (${e.code()}): ${e.message}")
            }
            Pair(null, emptyList())
        } catch (e: Exception) {
            Log.w(TAG, "getChurnRisk failed: ${e.message}")
            Pair(null, emptyList())
        }
    }

    /**
     * §3.2 L504 — Fetch cash-trapped inventory data from GET /reports/cash-trapped.
     *
     * Returns null on 404 (endpoint not yet live) so [CashTrappedCard] shows
     * the "Connect Inventory data" stub rather than crashing.
     */
    suspend fun getCashTrapped(): CashTrappedData? {
        if (!serverMonitor.isEffectivelyOnline.value) return null
        return try {
            val response = reportApi.getCashTrapped()
            response.data
        } catch (e: HttpException) {
            if (e.code() != 404) {
                Log.w(TAG, "getCashTrapped failed (${e.code()}): ${e.message}")
            }
            null
        } catch (e: Exception) {
            Log.w(TAG, "getCashTrapped failed: ${e.message}")
            null
        }
    }

    val lastSyncAt: String? get() = appPreferences.lastFullSyncAt

    private fun cachedStats() = DashboardStats(
        openTickets = appPreferences.cachedOpenTickets,
        revenueToday = appPreferences.cachedRevenueToday,
        isFromCache = true,
    )

    private fun cachedAttention() = NeedsAttention(
        lowStockCount = appPreferences.cachedLowStock,
        missingPartsCount = appPreferences.cachedMissingParts,
        staleTicketsCount = appPreferences.cachedStaleTickets,
        overdueInvoicesCount = appPreferences.cachedOverdueInvoices,
        isFromCache = true,
    )

    companion object {
        private const val TAG = "DashboardRepository"
    }
}
