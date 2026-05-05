package com.bizarreelectronics.crm.ui.screens.financial

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.prefs.PinPreferences
import com.bizarreelectronics.crm.data.remote.api.ReportApi
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import retrofit2.HttpException
import javax.inject.Inject

// ─── UI state models ─────────────────────────────────────────────────────────

/**
 * §62.1 — P&L snapshot from `/reports/pl-summary`.
 * All monetary values are in cents (Long).
 */
data class PLSummary(
    val revenueCents: Long = 0L,
    val cogsCents: Long = 0L,
    val grossMarginCents: Long = 0L,
    val opexCents: Long = 0L,
    val netIncomeCents: Long = 0L,
    /** Period-over-period % change (null = not available). */
    val periodChangePct: Double? = null,
)

/**
 * §62.2 — Cash flow forecast from `/reports/cashflow`.
 * All monetary values are in cents (Long).
 */
data class CashFlowForecast(
    val invoicesDueCents: Long = 0L,
    val recurringExpensesCents: Long = 0L,
    val projected30dCents: Long = 0L,
    val projected60dCents: Long = 0L,
    val projected90dCents: Long = 0L,
)

/**
 * §62.3 — A single jurisdiction row from `/reports/expense-breakdown` (tax section).
 */
data class TaxJurisdictionRow(
    val jurisdiction: String,
    val collectedCents: Long,
    val remittedCents: Long,
    val isRemitted: Boolean,
)

/**
 * §62.4 — A single category row for budget-vs-actual.
 */
data class BudgetActualRow(
    val category: String,
    val budgetCents: Long,
    val actualCents: Long,
)

/**
 * Full UI state for [FinancialDashboardScreen].
 *
 * [plSummary] / [cashFlow] are null when the server endpoint hasn't responded yet
 * (or doesn't exist) — the screen renders "coming soon" stubs in that case.
 * [taxRows] / [budgetRows] are empty lists for the same reason.
 */
data class FinancialDashboardUiState(
    val isLoading: Boolean = true,
    val error: String? = null,
    /** §62.5 — true when PinPreferences.isPinSet is true; drives PIN re-prompt. */
    val isPinConfigured: Boolean = false,
    /** §62.1 P&L snapshot; null until server responds. */
    val plSummary: PLSummary? = null,
    /** §62.2 Cash flow forecast; null until server responds. */
    val cashFlow: CashFlowForecast? = null,
    /** §62.3 Tax jurisdiction rows; empty until server responds. */
    val taxRows: List<TaxJurisdictionRow> = emptyList(),
    /** §62.4 Budget vs actual rows; empty until server responds. */
    val budgetRows: List<BudgetActualRow> = emptyList(),
    /** One-shot snackbar message (null = none pending). */
    val snackbarMessage: String? = null,
)

// ─── ViewModel ───────────────────────────────────────────────────────────────

/**
 * §62 — ViewModel for [FinancialDashboardScreen].
 *
 * Loads P&L, cash-flow, tax and budget data from the three owner-only report
 * endpoints.  All three endpoints are currently absent from the server so each
 * call gracefully no-ops on 404 / connection-refused; the UI shows stubs.
 *
 * A 403 is treated as an access-denied snackbar rather than a hard error so the
 * screen can still render with the role-gate message rather than a blank error state.
 *
 * PIN re-prompt: [isPinConfigured] is seeded synchronously from [PinPreferences]
 * at construction time so the screen can show the PIN dialog before any network
 * call is made.
 */
@HiltViewModel
class FinancialDashboardViewModel @Inject constructor(
    private val reportApi: ReportApi,
    private val pinPreferences: PinPreferences,
) : ViewModel() {

    companion object {
        private const val TAG = "FinancialDashboardVM"
    }

    private val _uiState = MutableStateFlow(
        FinancialDashboardUiState(
            isPinConfigured = pinPreferences.isPinSet,
        ),
    )
    val uiState: StateFlow<FinancialDashboardUiState> = _uiState.asStateFlow()

    init {
        load()
    }

    // ─── Public API ──────────────────────────────────────────────────────────

    /** Reload all financial data (e.g. on retry after error). */
    fun load() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }
            loadPLSummary()
            loadCashFlow()
            loadExpenseBreakdown()
            // §62.4 Budget: no server endpoint — leave budgetRows empty.
            _uiState.update { it.copy(isLoading = false) }
        }
    }

    /**
     * §62.5 — Verify a PIN locally using [PinPreferences.verifyPinLocally].
     * Returns true on match; false on mismatch (caller handles retry logic).
     */
    fun verifyPin(pin: String): Boolean = pinPreferences.verifyPinLocally(pin)

    /** Consume the pending snackbar message after it has been shown. */
    fun clearSnackbar() {
        _uiState.update { it.copy(snackbarMessage = null) }
    }

    // ─── Private loaders ─────────────────────────────────────────────────────

    /**
     * §62.1 — Load P&L snapshot from `/reports/pl-summary`.
     *
     * 404 → no-op (endpoint not yet deployed; plSummary stays null → stub shown).
     * 403 → snackbar; plSummary stays null.
     * Network error → no-op (offline tolerance; stub shown).
     */
    private suspend fun loadPLSummary() {
        try {
            val response = reportApi.getPLSummary()
            val data = response.data ?: return
            val revenue = (data["revenue_cents"] as? Number)?.toLong() ?: 0L
            val cogs = (data["cogs_cents"] as? Number)?.toLong() ?: 0L
            val grossMargin = (data["gross_margin_cents"] as? Number)?.toLong() ?: (revenue - cogs)
            val opex = (data["opex_cents"] as? Number)?.toLong() ?: 0L
            val netIncome = (data["net_income_cents"] as? Number)?.toLong() ?: (grossMargin - opex)
            val changePct = (data["period_change_pct"] as? Number)?.toDouble()
            _uiState.update {
                it.copy(
                    plSummary = PLSummary(
                        revenueCents = revenue,
                        cogsCents = cogs,
                        grossMarginCents = grossMargin,
                        opexCents = opex,
                        netIncomeCents = netIncome,
                        periodChangePct = changePct,
                    ),
                )
            }
        } catch (e: HttpException) {
            if (e.code() == 403) {
                _uiState.update { it.copy(snackbarMessage = "Access denied: owner role required") }
            }
            // 404 or other → leave plSummary null (stub shown)
        } catch (_: Exception) {
            // Network unreachable or serialisation error → leave stub shown
        }
    }

    /**
     * §62.2 — Load cash flow forecast from `/reports/cashflow`.
     *
     * Same tolerance policy as [loadPLSummary].
     */
    private suspend fun loadCashFlow() {
        try {
            val response = reportApi.getCashFlow()
            val data = response.data ?: return
            val invoicesDue = (data["invoices_due_cents"] as? Number)?.toLong() ?: 0L
            val recurring = (data["recurring_expenses_cents"] as? Number)?.toLong() ?: 0L
            val proj30 = (data["projected_30d_cents"] as? Number)?.toLong() ?: 0L
            val proj60 = (data["projected_60d_cents"] as? Number)?.toLong() ?: 0L
            val proj90 = (data["projected_90d_cents"] as? Number)?.toLong() ?: 0L
            _uiState.update {
                it.copy(
                    cashFlow = CashFlowForecast(
                        invoicesDueCents = invoicesDue,
                        recurringExpensesCents = recurring,
                        projected30dCents = proj30,
                        projected60dCents = proj60,
                        projected90dCents = proj90,
                    ),
                )
            }
        } catch (e: HttpException) {
            if (e.code() == 403) {
                _uiState.update { it.copy(snackbarMessage = "Access denied: owner role required") }
            }
        } catch (_: Exception) {
            // Offline / not deployed → stub shown
        }
    }

    /**
     * §62.3 — Load tax liability from `/reports/expense-breakdown`.
     *
     * Expected shape: `{ jurisdictions: [{ name, collected_cents, remitted_cents, is_remitted }] }`
     * Same tolerance policy as above.
     */
    private suspend fun loadExpenseBreakdown() {
        try {
            val response = reportApi.getExpenseBreakdown()
            val data = response.data ?: return
            @Suppress("UNCHECKED_CAST")
            val jurisdictions = data["jurisdictions"] as? List<Map<String, Any?>> ?: return
            val rows = jurisdictions.map { j ->
                TaxJurisdictionRow(
                    jurisdiction = j["name"] as? String ?: "",
                    collectedCents = (j["collected_cents"] as? Number)?.toLong() ?: 0L,
                    remittedCents = (j["remitted_cents"] as? Number)?.toLong() ?: 0L,
                    isRemitted = j["is_remitted"] as? Boolean ?: false,
                )
            }
            _uiState.update { it.copy(taxRows = rows) }
        } catch (e: HttpException) {
            if (e.code() == 403) {
                _uiState.update { it.copy(snackbarMessage = "Access denied: owner role required") }
            }
        } catch (_: Exception) {
            // Offline / not deployed → stub shown
        }
    }
}
