package com.bizarreelectronics.crm.widget.glance

import androidx.glance.appwidget.GlanceAppWidgetReceiver

/**
 * §24.1 — BroadcastReceiver entry point for the Clock-In/Out Glance widget.
 *
 * Delegates all AppWidget lifecycle broadcasts (UPDATE, DELETED, ENABLED,
 * DISABLED) to [ClockInGlanceWidget] via [GlanceAppWidgetReceiver].
 *
 * No Hilt injection — see [UnreadSmsGlanceReceiver] for the rationale.
 * State is pushed externally via [publishClockState].
 *
 * Declared in AndroidManifest.xml with `android:exported="false"` — only the
 * platform AppWidget framework sends APPWIDGET_UPDATE broadcasts.
 */
class ClockInGlanceReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: ClockInGlanceWidget = ClockInGlanceWidget()
}
