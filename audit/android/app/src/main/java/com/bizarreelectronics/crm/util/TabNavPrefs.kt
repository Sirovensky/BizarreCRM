package com.bizarreelectronics.crm.util

/**
 * §1.5 line 202 — tab navigation order helpers.
 *
 * Encapsulates serialisation and validation for the user-reorderable bottom-nav
 * tab order. The five primary-tab route identifiers are:
 *
 *   "dashboard", "tickets", "pos", "messages", "more"
 *
 * Rules:
 *  - "more" is always the last tab and cannot be moved by the user.
 *  - The four configurable slots are: dashboard, tickets, pos, messages.
 *  - If the stored order is missing a canonical tab, the default fills the gap
 *    so the bar is never incomplete (forward-compat: adding a new tab later
 *    won't corrupt existing persisted orderings).
 *  - Unknown tokens are stripped so stale route names from old builds don't
 *    appear as phantom tabs.
 */
object TabNavPrefs {

    /** Routes that the user can reorder (excludes "more" which is always last). */
    val REORDERABLE_TABS: List<String> = listOf(
        "dashboard",
        "tickets",
        "pos",
        "messages",
    )

    /** The "More" overflow route is always appended last and is not reorderable. */
    const val MORE_TAB = "more"

    /**
     * Decode a persisted comma-separated route string into an ordered list of
     * four reorderable route identifiers.
     *
     * - Empty / blank input → [REORDERABLE_TABS] (default order).
     * - Unknown tokens are stripped.
     * - Missing canonical tabs are appended at the end (in default order) so
     *   the result always contains exactly [REORDERABLE_TABS].size entries.
     */
    fun decodeOrder(raw: String): List<String> {
        if (raw.isBlank()) return REORDERABLE_TABS

        val stored = raw.split(",")
            .map { it.trim() }
            .filter { it in REORDERABLE_TABS }
            .distinct()

        // Add any canonical tabs missing from the stored list (preserves order of
        // stored entries, fills gaps with the defaultorder of remaining tabs).
        val missing = REORDERABLE_TABS.filter { it !in stored }
        return stored + missing
    }

    /**
     * Encode an ordered list of route identifiers to a comma-separated string
     * suitable for storing in [AppPreferences.tabNavOrder].
     *
     * Unknown or duplicate tokens are silently dropped. The "more" tab must not
     * be included in [order] — it is always appended by the nav bar itself.
     */
    fun encodeOrder(order: List<String>): String =
        order
            .filter { it in REORDERABLE_TABS }
            .distinct()
            .joinToString(",")

    /**
     * Move the tab at [fromIndex] to [toIndex] within [current], returning the
     * new list. Indices outside [0, current.size) are clamped silently.
     */
    fun move(current: List<String>, fromIndex: Int, toIndex: Int): List<String> {
        if (fromIndex == toIndex) return current
        val mutable = current.toMutableList()
        val from = fromIndex.coerceIn(mutable.indices)
        val to = toIndex.coerceIn(mutable.indices)
        val item = mutable.removeAt(from)
        mutable.add(to, item)
        return mutable
    }

    /** Human-readable label for a tab route identifier. */
    fun labelFor(route: String): String = when (route) {
        "dashboard" -> "Dashboard"
        "tickets"   -> "Tickets"
        "pos"       -> "POS"
        "messages"  -> "Messages"
        else        -> route.replaceFirstChar { it.uppercase() }
    }
}
