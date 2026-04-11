package com.bizarreelectronics.crm.widget

// -----------------------------------------------------------------------------
// NOTE: This widget is built with the classic RemoteViews API (stable since
// API 3), NOT androidx.glance. It therefore requires no additional Gradle
// dependencies. If you later want to migrate to Glance for Compose parity,
// add: implementation("androidx.glance:glance-appwidget:1.1.0")
// and rewrite the provider to extend GlanceAppWidget / GlanceAppWidgetReceiver.
// -----------------------------------------------------------------------------

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import com.bizarreelectronics.crm.MainActivity
import com.bizarreelectronics.crm.R
import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
import dagger.hilt.EntryPoint
import dagger.hilt.InstallIn
import dagger.hilt.android.EntryPointAccessors
import dagger.hilt.components.SingletonComponent

/**
 * Home-screen widget displaying a glanceable summary:
 *   - Revenue today
 *   - Open tickets
 *   - Low stock count
 *
 * The widget does NOT hit the network. It reads the values cached by the
 * dashboard load (see [AppPreferences.cachedRevenueToday] et al). A foreground
 * sync through the app will update those cached values, and this provider
 * then refreshes on its own 30-minute cadence (declared in widget_info.xml)
 * plus any ACTION_APPWIDGET_UPDATE broadcast from [updateAll].
 *
 * Tapping anywhere on the widget opens MainActivity. Whole-widget click is
 * the lowest-effort glanceable pattern; dedicated cell taps would require
 * RemoteViews setOnClickPendingIntent on each TextView and are a future
 * improvement once we have deep-link routes for each metric.
 *
 * Hilt integration uses EntryPoint rather than @AndroidEntryPoint because
 * BroadcastReceiver subclasses cannot be annotated by Hilt directly — this is
 * the documented workaround from the Hilt docs.
 */
class DashboardWidgetProvider : AppWidgetProvider() {

    @EntryPoint
    @InstallIn(SingletonComponent::class)
    interface WidgetEntryPoint {
        fun appPreferences(): AppPreferences
    }

    /**
     * Defence-in-depth: the receiver is exported=true so the launcher can bind
     * to it, which means any other app on the device could in theory send us
     * a broadcast by targeting our component directly. [AppWidgetProvider]
     * already dispatches only known system actions to their respective
     * callbacks, but we tighten that to a strict whitelist so an attacker
     * cannot trigger, say, onEnabled with attacker-supplied extras. Anything
     * not on the whitelist is dropped before it reaches the parent handler.
     */
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        val allowed = action == AppWidgetManager.ACTION_APPWIDGET_UPDATE ||
            action == AppWidgetManager.ACTION_APPWIDGET_ENABLED ||
            action == AppWidgetManager.ACTION_APPWIDGET_DISABLED ||
            action == AppWidgetManager.ACTION_APPWIDGET_DELETED ||
            action == AppWidgetManager.ACTION_APPWIDGET_OPTIONS_CHANGED
        if (!allowed) return
        super.onReceive(context, intent)
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        val prefs = EntryPointAccessors.fromApplication(
            context.applicationContext,
            WidgetEntryPoint::class.java,
        ).appPreferences()

        appWidgetIds.forEach { widgetId ->
            val views = buildViews(context, prefs)
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun buildViews(context: Context, prefs: AppPreferences): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_dashboard)

        val revenue = "$" + String.format("%.2f", prefs.cachedRevenueToday)
        views.setTextViewText(R.id.widget_revenue_value, revenue)
        views.setTextViewText(R.id.widget_open_tickets_value, prefs.cachedOpenTickets.toString())
        views.setTextViewText(R.id.widget_low_stock_value, prefs.cachedLowStock.toString())

        // Tap anywhere → open the app.
        val launchIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)

        return views
    }

    companion object {
        /**
         * Call this after the dashboard finishes loading so the widget can
         * pull fresh numbers from [AppPreferences]. Safe to call from any
         * thread — [AppWidgetManager.updateAppWidget] is thread-safe.
         */
        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, DashboardWidgetProvider::class.java)
            val ids = manager.getAppWidgetIds(component)
            if (ids.isEmpty()) return
            // Explicit intent targeted at our own package/component — prevents
            // the broadcast from leaking to other apps that may share the
            // APPWIDGET_UPDATE action.
            val intent = Intent(context, DashboardWidgetProvider::class.java).apply {
                action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                setPackage(context.packageName)
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
            }
            context.sendBroadcast(intent)
        }
    }
}
