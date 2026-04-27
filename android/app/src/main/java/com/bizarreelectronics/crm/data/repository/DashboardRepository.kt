package com.bizarreelectronics.crm.data.repository

import android.util.Log
import com.bizarreelectronics.crm.data.local.db.dao.TicketDao
import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.remote.api.ReportApi
import com.bizarreelectronics.crm.data.remote.api.TicketApi
import com.bizarreelectronics.crm.data.remote.dto.TicketListItem
import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
import kotlinx.coroutines.flow.Flow
import javax.inject.Inject
import javax.inject.Singleton

data class DashboardStats(
    val openTickets: Int = 0,
    val revenueToday: Double = 0.0,
    val appointmentsToday: Int = 0,
    val ticketsDueToday: Int = 0,
    val isFromCache: Boolean = false,
    // §3 L489 — web-mirror KPI fields. All default 0/0.0; populated when
    // the server includes the field in GET /reports/dashboard response.
    val taxToday: Double = 0.0,
    val discountsToday: Double = 0.0,
    val cogsToday: Double = 0.0,
    val netProfitToday: Double = 0.0,
    val refundsToday: Double = 0.0,
    val expensesToday: Double = 0.0,
    val receivablesTotal: Double = 0.0,
    val closedToday: Int = 0,
)

/**
 * §3.2 L504 — Summary of overdue receivables for the Cash-Trapped card.
 *
 * @property overdueReceivablesCents Total overdue balance in cents.
 * @property overdueCount            Number of overdue invoices.
 *
 * Null instance returned by [DashboardRepository.getAgingSummary] when the
 * endpoint returns HTTP 404 (not yet implemented) or the device is offline.
 */
data class AgingSummary(
    val overdueReceivablesCents: Long,
    val overdueCount: Int,
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
                    // §3 L489 — web-mirror fields; zero when absent (server hasn't added them yet).
                    taxToday = (data["tax_today"] as? Number)?.toDouble() ?: 0.0,
                    discountsToday = (data["discounts_today"] as? Number)?.toDouble() ?: 0.0,
                    cogsToday = (data["cogs_today"] as? Number)?.toDouble() ?: 0.0,
                    netProfitToday = (data["net_profit_today"] as? Number)?.toDouble() ?: 0.0,
                    refundsToday = (data["refunds_today"] as? Number)?.toDouble() ?: 0.0,
                    expensesToday = (data["expenses_today"] as? Number)?.toDouble() ?: 0.0,
                    receivablesTotal = (data["receivables_total"] as? Number)?.toDouble() ?: 0.0,
                    closedToday = (data["closed_today"] as? Number)?.toInt() ?: 0,
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
     * §3.2 L504 — Fetch overdue-receivables summary from `GET /reports/aging`.
     *
     * Returns null when:
     * - Device is offline.
     * - Server returns HTTP 404 (endpoint not yet implemented).
     * - Any other network error.
     *
     * The caller ([DashboardViewModel]) renders [CashTrappedCard] in its
     * empty state when null is returned — no crash, no stale data.
     */
    suspend fun getAgingSummary(): AgingSummary? {
        if (!serverMonitor.isEffectivelyOnline.value) return null
        return try {
            val response = reportApi.getAging()
            val data = response.data ?: return null
            AgingSummary(
                overdueReceivablesCents = (data["overdue_total_cents"] as? Number)?.toLong() ?: 0L,
                overdueCount = (data["overdue_count"] as? Number)?.toInt() ?: 0,
            )
        } catch (e: retrofit2.HttpException) {
            if (e.code() == 404) {
                Log.d(TAG, "getAging: endpoint not yet live (404) — Cash-Trapped card will show empty state")
            } else {
                Log.w(TAG, "getAging failed (${e.code()}): ${e.message}")
            }
            null
        } catch (e: Exception) {
            Log.w(TAG, "getAging error: ${e.message}")
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
