package com.bizarreelectronics.crm.util

/**
 * §18.1 — recent-searches cache helper.
 *
 * Pure list math kept out of [com.bizarreelectronics.crm.data.local.prefs.AppPreferences]
 * so unit tests can exercise dedupe + cap without touching SharedPreferences.
 *
 * Contract:
 *  - Most-recent entry lives at index 0.
 *  - New queries are trimmed and blank queries are rejected (no-op).
 *  - Matching existing entries are removed before re-inserting at index 0 so a
 *    search for the same term shuffles it back to the front instead of
 *    creating a duplicate.
 *  - Match is case-insensitive: "iPhone" == "iphone" == "IPHONE".
 *  - The list is capped at [LIMIT] entries (oldest dropped).
 */
object RecentSearches {

    const val LIMIT = 8

    /**
     * Returns a new list with [query] prepended. Does not mutate [current].
     * Returns [current] unchanged if [query] is blank.
     */
    fun prepend(current: List<String>, query: String): List<String> {
        val trimmed = query.trim()
        if (trimmed.isEmpty()) return current
        val filtered = current.filterNot { it.equals(trimmed, ignoreCase = true) }
        return (listOf(trimmed) + filtered).take(LIMIT)
    }

    /**
     * Remove a single entry (case-insensitive match). Returns [current]
     * unchanged when not found.
     */
    fun remove(current: List<String>, query: String): List<String> {
        val trimmed = query.trim()
        if (trimmed.isEmpty()) return current
        return current.filterNot { it.equals(trimmed, ignoreCase = true) }
    }

    /**
     * Serialize to a single string for SharedPreferences storage. Uses \u0001
     * as the separator since it cannot appear in a user-typed query.
     */
    fun serialize(list: List<String>): String = list.joinToString("\u0001")

    /**
     * Inverse of [serialize]. Tolerates the empty string and any stray
     * separators. Applies [LIMIT] defensively in case the stored list
     * predates a limit change.
     */
    fun deserialize(raw: String?): List<String> {
        if (raw.isNullOrEmpty()) return emptyList()
        return raw.split('\u0001').filter { it.isNotBlank() }.take(LIMIT)
    }
}
