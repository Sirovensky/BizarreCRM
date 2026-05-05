package com.bizarreelectronics.crm.widget.glance

import androidx.glance.appwidget.GlanceAppWidgetReceiver

/**
 * §24.1 — BroadcastReceiver entry point for the Low-Stock Glance widget.
 *
 * Delegates all AppWidget lifecycle broadcasts to [LowStockGlanceWidget].
 * No Hilt — state is pushed via [publishLowStockCount].
 *
 * Declared in AndroidManifest.xml with `android:exported="false"`.
 */
class LowStockGlanceReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: LowStockGlanceWidget = LowStockGlanceWidget()
}
