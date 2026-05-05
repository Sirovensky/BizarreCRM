package com.bizarreelectronics.crm.widget.glance

import androidx.glance.appwidget.GlanceAppWidgetReceiver

/**
 * BroadcastReceiver entry point for the Unread SMS Glance widget.
 *
 * Extends [GlanceAppWidgetReceiver], which handles all standard
 * `APPWIDGET_UPDATE` / `APPWIDGET_DELETED` / `APPWIDGET_ENABLED` /
 * `APPWIDGET_DISABLED` broadcasts and delegates them to [UnreadSmsGlanceWidget].
 *
 * **Hilt-free by design**: Glance receivers should NOT use
 * `@AndroidEntryPoint` because [GlanceAppWidgetReceiver] manages its own
 * coroutine lifecycle internally.  If repository access is needed in the
 * future, use a [androidx.work.CoroutineWorker] launched from
 * [onUpdate] and wire Hilt via [androidx.hilt.work.HiltWorker].
 *
 * Declared in `AndroidManifest.xml` with `android:exported="false"` because
 * only the system AppWidget framework (signed with the platform certificate)
 * sends `ACTION_APPWIDGET_UPDATE` — no other app can target this receiver.
 */
class UnreadSmsGlanceReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: UnreadSmsGlanceWidget = UnreadSmsGlanceWidget()
}
