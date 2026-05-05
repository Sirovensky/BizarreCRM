package com.bizarreelectronics.crm.widget.glance

/**
 * Glance DataStore key constants shared between the widgets and any caller
 * that wants to push updated state into them.
 *
 * Only preference-backed state lives here — no repository or network access.
 * Writes go through the publish helpers in each widget file:
 *   [UnreadSmsGlanceWidget.publishUnreadCount]
 *   [ClockInGlanceWidget.publishClockState]
 *   [LowStockGlanceWidget.publishLowStockCount]
 *
 * Readers access these keys via
 * [androidx.glance.appwidget.state.getAppWidgetState].
 *
 * Keys
 * ----
 * [KEY_UNREAD_COUNT]    — Int count of unread SMS conversations.
 * [KEY_IS_CLOCKED_IN]  — Boolean current clock-in state.
 * [KEY_LOW_STOCK_COUNT] — Int number of items below reorder level.
 * [KEY_REVENUE_TODAY]  — Float today's revenue (see [TodayRevenueWidgetKeys]).
 * [KEY_OPEN_TICKETS]   — Int open ticket count (see [TodayRevenueWidgetKeys]).
 *
 * Absent (null) means "never populated yet" and widgets display "—" or a
 * safe default until the first push arrives.
 */
object GlanceWidgetKeys {
    /** Preference key for unread SMS count. Written by [publishUnreadCount]. */
    const val KEY_UNREAD_COUNT = "unread_count"

    /**
     * Boolean preference key for the current clock-in state.
     * Written by [publishClockState]; read by [ClockInGlanceWidget].
     * Absent (null) treated as false (clocked out).
     */
    const val KEY_IS_CLOCKED_IN = "is_clocked_in"

    /**
     * Int preference key for the number of inventory items below reorder level.
     * Written by [publishLowStockCount]; read by [LowStockGlanceWidget].
     * Absent (null) rendered as "—" until first inventory sync.
     */
    const val KEY_LOW_STOCK_COUNT = "low_stock_count"

    /**
     * Float preference key for today's revenue in USD.
     * Written by [publishTodayRevenue]; read by [TodayRevenueGlanceWidget].
     * Absent (null) rendered as "—" until the first dashboard sync.
     * Mirrors [TodayRevenueWidgetKeys.KEY_REVENUE_TODAY].
     */
    const val KEY_REVENUE_TODAY = TodayRevenueWidgetKeys.KEY_REVENUE_TODAY

    /**
     * Int preference key for the current open ticket count.
     * Written by [publishTodayRevenue]; read by [TodayRevenueGlanceWidget].
     * Absent (null) rendered as "—" until the first dashboard sync.
     * Mirrors [TodayRevenueWidgetKeys.KEY_OPEN_TICKETS].
     */
    const val KEY_OPEN_TICKETS = TodayRevenueWidgetKeys.KEY_OPEN_TICKETS
}
