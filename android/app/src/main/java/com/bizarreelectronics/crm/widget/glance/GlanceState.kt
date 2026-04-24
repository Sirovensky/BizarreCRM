package com.bizarreelectronics.crm.widget.glance

/**
 * Glance DataStore key constants shared between the widget and any caller
 * that wants to push updated state into it.
 *
 * Only preference-backed state lives here — no repository or network access.
 * All writes go through [UnreadSmsGlanceWidget.publishUnreadCount]; readers
 * access these keys via [androidx.glance.appwidget.state.getAppWidgetState].
 *
 * Keys
 * ----
 * [KEY_UNREAD_COUNT] — Int count of unread SMS conversations.  Absent (null)
 * means "never populated yet", displayed as "—" in the widget.
 */
object GlanceWidgetKeys {
    /** Preference key for unread SMS count written by [UnreadSmsGlanceWidget.publishUnreadCount]. */
    const val KEY_UNREAD_COUNT = "unread_count"
}
