package com.bizarreelectronics.crm.widget.glance

import androidx.glance.appwidget.GlanceAppWidgetReceiver

/**
 * §24.1 — AppWidget broadcast receiver for [TodayRevenueGlanceWidget].
 *
 * Registered in AndroidManifest.xml with `android.appwidget.action.APPWIDGET_UPDATE`
 * and metadata pointing to `@xml/glance_today_revenue_info`. All standard lifecycle
 * broadcasts (UPDATE / ENABLED / DISABLED / DELETED) are handled by
 * [GlanceAppWidgetReceiver] automatically.
 */
class TodayRevenueGlanceReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = TodayRevenueGlanceWidget()
}
