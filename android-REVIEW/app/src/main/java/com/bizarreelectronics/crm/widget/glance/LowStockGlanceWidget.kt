package com.bizarreelectronics.crm.widget.glance

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.datastore.preferences.core.Preferences
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
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.state.GlanceStateDefinition
import androidx.glance.state.PreferencesGlanceStateDefinition
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import com.bizarreelectronics.crm.MainActivity
import com.bizarreelectronics.crm.widget.glance.LowStockWidgetKeys.KEY_LOW_STOCK_COUNT

/**
 * §24.1 — Glance home-screen widget showing the count of inventory items
 * that are at or below their reorder level.
 *
 * State is pushed by [publishLowStockCount] from the inventory sync path
 * (e.g. a [androidx.work.CoroutineWorker] that polls `/api/v1/inventory` and
 * counts items where `quantity <= reorderPoint`).
 *
 * Tapping the widget deep-links to `bizarrecrm://inventory?filter=low_stock`
 * so the user lands directly on the filtered inventory list.
 *
 * Theme tokens come from [GlanceTheme] — no hardcoded colors.
 */
class LowStockGlanceWidget : GlanceAppWidget() {

    override val stateDefinition: GlanceStateDefinition<*> = PreferencesGlanceStateDefinition

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent {
            GlanceTheme {
                LowStockWidgetBody(context = context)
            }
        }
    }
}

// ── Private composable ─────────────────────────────────────────────────────

@Composable
private fun LowStockWidgetBody(context: Context) {
    val prefs = currentState<Preferences>()
    val count: Int? = prefs[intPreferencesKey(KEY_LOW_STOCK_COUNT)]
    val countText = count?.toString() ?: "—" // em dash while not yet populated

    // Tap navigates to inventory list filtered to low-stock items.
    val tapIntent = Intent(context, MainActivity::class.java).apply {
        data = Uri.parse("bizarrecrm://inventory?filter=low_stock")
        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
    }

    // Use error/warning color from GlanceTheme when there are low-stock items.
    val countColor = if ((count ?: 0) > 0) GlanceTheme.colors.error
                     else GlanceTheme.colors.primary

    Column(
        modifier = GlanceModifier
            .fillMaxSize()
            .background(GlanceTheme.colors.surface)
            .padding(horizontal = 12.dp, vertical = 8.dp)
            .clickable(actionStartActivity(tapIntent)),
        verticalAlignment = Alignment.Vertical.CenterVertically,
        horizontalAlignment = Alignment.Horizontal.CenterHorizontally,
    ) {
        Text(
            text = "Low Stock",
            style = TextStyle(
                color = GlanceTheme.colors.onSurface,
                fontSize = 12.sp,
                fontWeight = FontWeight.Medium,
            ),
            modifier = GlanceModifier.fillMaxWidth(),
        )

        Spacer(modifier = GlanceModifier.height(4.dp))

        Text(
            text = countText,
            style = TextStyle(
                color = countColor,
                fontSize = 32.sp,
                fontWeight = FontWeight.Bold,
            ),
            modifier = GlanceModifier.fillMaxWidth(),
        )

        Spacer(modifier = GlanceModifier.height(4.dp))

        Text(
            text = "items below reorder level",
            style = TextStyle(
                color = GlanceTheme.colors.onSurfaceVariant,
                fontSize = 10.sp,
            ),
            modifier = GlanceModifier.fillMaxWidth(),
        )
    }
}

// ── Public state-update helper ─────────────────────────────────────────────

/**
 * Writes [count] into the Glance DataStore for every active [LowStockGlanceWidget]
 * instance and triggers a UI refresh.
 *
 * Call from the inventory sync worker:
 * ```kotlin
 * val lowStockCount = inventoryDao.countBelowReorderLevel()
 * publishLowStockCount(applicationContext, lowStockCount)
 * ```
 *
 * @param context Application context.
 * @param count   Number of inventory items at or below their reorder level.
 */
suspend fun publishLowStockCount(context: Context, count: Int) {
    val widget = LowStockGlanceWidget()
    val glanceIds = GlanceAppWidgetManager(context)
        .getGlanceIds(LowStockGlanceWidget::class.java)

    glanceIds.forEach { glanceId ->
        updateAppWidgetState(context, PreferencesGlanceStateDefinition, glanceId) {
            it.toMutablePreferences().also { m ->
                m[intPreferencesKey(KEY_LOW_STOCK_COUNT)] = count
            }
        }
        widget.update(context, glanceId)
    }
}

// ── Key constants ──────────────────────────────────────────────────────────

object LowStockWidgetKeys {
    const val KEY_LOW_STOCK_COUNT = "low_stock_count"
}
