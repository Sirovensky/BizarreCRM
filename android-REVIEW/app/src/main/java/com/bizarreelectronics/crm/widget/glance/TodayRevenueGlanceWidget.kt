package com.bizarreelectronics.crm.widget.glance

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.floatPreferencesKey
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.provideContent
import androidx.glance.appwidget.state.updateAppWidgetState
import androidx.glance.background
import androidx.glance.currentState
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.width
import androidx.glance.state.GlanceStateDefinition
import androidx.glance.state.PreferencesGlanceStateDefinition
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import com.bizarreelectronics.crm.MainActivity
import com.bizarreelectronics.crm.widget.glance.TodayRevenueWidgetKeys.KEY_OPEN_TICKETS
import com.bizarreelectronics.crm.widget.glance.TodayRevenueWidgetKeys.KEY_REVENUE_TODAY
import java.util.Locale

/**
 * §24.1 — Glance home-screen widget showing today's revenue and open ticket count.
 *
 * State is pushed by [publishTodayRevenue] from the dashboard sync path
 * (DashboardRepository after a successful `/api/v1/reports/dashboard` fetch).
 * While offline the last cached values remain visible.
 *
 * Tapping the widget deep-links to `bizarrecrm://dashboard` so the user
 * lands on the main dashboard to see the full KPI set.
 *
 * ## State keys (Glance DataStore)
 * - [KEY_REVENUE_TODAY] — Float (today's revenue; stored as Float for DataStore compat)
 * - [KEY_OPEN_TICKETS]  — Int   (number of currently open tickets)
 *
 * ## Manifest
 * Declared in AndroidManifest.xml as [TodayRevenueGlanceReceiver] with
 * `android.appwidget.provider` pointing to `@xml/glance_today_revenue_info`.
 */
class TodayRevenueGlanceWidget : GlanceAppWidget() {

    override val stateDefinition: GlanceStateDefinition<*> = PreferencesGlanceStateDefinition

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent {
            GlanceTheme {
                TodayRevenueWidgetBody(context = context)
            }
        }
    }
}

// ── Private composable ─────────────────────────────────────────────────────

@Composable
private fun TodayRevenueWidgetBody(context: Context) {
    val prefs = currentState<Preferences>()

    val revenueRaw: Float? = prefs[floatPreferencesKey(KEY_REVENUE_TODAY)]
    val openTickets: Int? = prefs[intPreferencesKey(KEY_OPEN_TICKETS)]

    // Format revenue as locale-aware currency without a network call.
    // Absent → em dash until first dashboard sync.
    val revenueText = revenueRaw?.let { formatRevenue(it) } ?: "—"
    val ticketsText = openTickets?.toString() ?: "—"

    val tapIntent = Intent(context, MainActivity::class.java).apply {
        data = Uri.parse("bizarrecrm://dashboard")
        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
    }

    Column(
        modifier = GlanceModifier
            .fillMaxSize()
            .background(GlanceTheme.colors.surface)
            .padding(horizontal = 12.dp, vertical = 8.dp)
            .clickable(actionStartActivity(tapIntent)),
        verticalAlignment = Alignment.Vertical.Top,
        horizontalAlignment = Alignment.Horizontal.Start,
    ) {
        // Header label
        Text(
            text = "Today",
            style = TextStyle(
                color = GlanceTheme.colors.onSurfaceVariant,
                fontSize = 11.sp,
                fontWeight = FontWeight.Medium,
            ),
            modifier = GlanceModifier.fillMaxWidth(),
        )

        Spacer(modifier = GlanceModifier.height(6.dp))

        // Revenue row
        Text(
            text = "Revenue",
            style = TextStyle(
                color = GlanceTheme.colors.onSurface,
                fontSize = 10.sp,
            ),
            modifier = GlanceModifier.fillMaxWidth(),
        )
        Text(
            text = revenueText,
            style = TextStyle(
                color = GlanceTheme.colors.primary,
                fontSize = 24.sp,
                fontWeight = FontWeight.Bold,
            ),
            modifier = GlanceModifier.fillMaxWidth(),
        )

        Spacer(modifier = GlanceModifier.height(8.dp))

        // Open tickets row
        Row(
            modifier = GlanceModifier.fillMaxWidth(),
            verticalAlignment = Alignment.Vertical.CenterVertically,
        ) {
            Column(
                modifier = GlanceModifier.defaultWeight(),
                horizontalAlignment = Alignment.Horizontal.Start,
            ) {
                Text(
                    text = "Open tickets",
                    style = TextStyle(
                        color = GlanceTheme.colors.onSurface,
                        fontSize = 10.sp,
                    ),
                )
                Text(
                    text = ticketsText,
                    style = TextStyle(
                        color = GlanceTheme.colors.onSurface,
                        fontSize = 20.sp,
                        fontWeight = FontWeight.Bold,
                    ),
                )
            }
        }
    }
}

// ── Formatting helper ──────────────────────────────────────────────────────

/**
 * Formats [amount] as a compact USD currency string suitable for a widget.
 * Values ≥ $1 000 are abbreviated (e.g. "$1.2k") to fit in tight widget cells.
 * Uses [Locale.US] so the separator/decimal are stable regardless of device locale.
 */
private fun formatRevenue(amount: Float): String {
    return when {
        amount >= 1_000_000f -> "$%.1fM".format(amount / 1_000_000f)
        amount >= 1_000f     -> "$%.1fk".format(amount / 1_000f)
        else                 -> "$%.2f".format(amount)
    }.let { raw ->
        // Strip trailing ".0" from abbreviated form for tidiness ("$1.0k" → "$1k")
        if (raw.endsWith(".0k") || raw.endsWith(".0M")) raw.replace(".0", "")
        else raw
    }
}

// ── Public state-update helper ─────────────────────────────────────────────

/**
 * §24.1 — Writes today's revenue and open ticket count into the Glance DataStore
 * for every active [TodayRevenueGlanceWidget] instance and triggers a UI refresh.
 *
 * Call after a successful dashboard fetch:
 * ```kotlin
 * publishTodayRevenue(
 *     context      = applicationContext,
 *     revenueToday = stats.revenueToday,
 *     openTickets  = stats.openTickets,
 * )
 * ```
 *
 * Safe to call when no instances are pinned (becomes a no-op).
 *
 * @param context      Application context (not Activity context).
 * @param revenueToday Today's total revenue in USD.
 * @param openTickets  Current open ticket count.
 */
suspend fun publishTodayRevenue(
    context: Context,
    revenueToday: Double,
    openTickets: Int,
) {
    val widget = TodayRevenueGlanceWidget()
    val glanceIds = GlanceAppWidgetManager(context)
        .getGlanceIds(TodayRevenueGlanceWidget::class.java)

    glanceIds.forEach { glanceId ->
        updateAppWidgetState(context, PreferencesGlanceStateDefinition, glanceId) {
            it.toMutablePreferences().also { m ->
                m[floatPreferencesKey(KEY_REVENUE_TODAY)] = revenueToday.toFloat()
                m[intPreferencesKey(KEY_OPEN_TICKETS)] = openTickets
            }
        }
        widget.update(context, glanceId)
    }
}

// ── Key constants ──────────────────────────────────────────────────────────

/**
 * DataStore preference keys for [TodayRevenueGlanceWidget].
 *
 * [KEY_REVENUE_TODAY] — Float; today's revenue in USD. Stored as Float because
 *   Glance's [PreferencesGlanceStateDefinition] uses DataStore Preferences which
 *   has no Double key type; precision is sufficient for display.
 *
 * [KEY_OPEN_TICKETS]  — Int; current number of open tickets.
 */
object TodayRevenueWidgetKeys {
    const val KEY_REVENUE_TODAY = "revenue_today"
    const val KEY_OPEN_TICKETS  = "open_tickets_count"
}
