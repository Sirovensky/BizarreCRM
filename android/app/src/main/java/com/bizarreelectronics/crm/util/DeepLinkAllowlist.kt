package com.bizarreelectronics.crm.util

/**
 * §13.2 / §68.3 — allow-listed deep-link routes.
 *
 * Single source of truth for which `bizarrecrm://…` paths the app honors.
 * Extracted from [com.bizarreelectronics.crm.MainActivity] so the set can
 * be unit-tested without a Context.
 *
 * Any unknown route is dropped silently — callers fall back to the default
 * start destination (Dashboard) rather than land the user on an unexpected
 * screen via an injected intent.
 */
object DeepLinkAllowlist {

    /**
     * Routes the user-visible NavHost already wires. Keep this list in sync
     * with [com.bizarreelectronics.crm.ui.navigation.Screen] entries.
     *
     * Intentionally a small whitelist rather than a prefix check — each new
     * accepted route requires an explicit add here, which keeps the attack
     * surface to exactly the paths the nav graph handles.
     */
    val routes: Set<String> = setOf(
        "ticket/new",
        "customer/new",
        "scan",
    )

    /**
     * Returns the canonical route string when [candidate] is allow-listed,
     * otherwise null. Callers hand this value straight to [DeepLinkBus].
     */
    fun resolve(candidate: String?): String? {
        if (candidate.isNullOrBlank()) return null
        return if (candidate in routes) candidate else null
    }
}
