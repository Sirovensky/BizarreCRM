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
     * Token validation pattern for setup invite tokens.
     * Accepts 20–128 URL-safe base64 characters; rejects empty, too-short,
     * and any token containing a slash (path-traversal guard).
     */
    private val SETUP_TOKEN_PATTERN = Regex("^[A-Za-z0-9_-]{20,128}$")

    /**
     * Routes the user-visible NavHost already wires. Keep this list in sync
     * with [com.bizarreelectronics.crm.ui.navigation.Screen] entries.
     *
     * Intentionally a small whitelist rather than a prefix check — each new
     * accepted route requires an explicit add here, which keeps the attack
     * surface to exactly the paths the nav graph handles.
     *
     * Note: "setup" is not in this static set — it is handled dynamically by
     * [resolve] because it carries a token path segment.
     */
    val routes: Set<String> = setOf(
        "ticket/new",
        "customer/new",
        "scan",
    )

    /**
     * Returns the canonical route string when [candidate] is allow-listed,
     * otherwise null. Callers hand this value straight to [DeepLinkBus].
     *
     * §2.7 L330 — setup token handling:
     * A candidate of the form `"setup/<token>"` is recognised as a setup
     * invite deep link. The token is validated against [SETUP_TOKEN_PATTERN]
     * (non-empty, 20–128 URL-safe chars, no slashes). A valid token yields the
     * parametrized nav route `"login?setupToken=<token>"` so AppNavGraph can
     * deliver it to LoginScreen. Invalid or missing tokens fall through to null
     * (silent fallback to plain Login).
     */
    fun resolve(candidate: String?): String? {
        if (candidate.isNullOrBlank()) return null

        // §2.7 L330 — setup invite: "setup/<token>"
        if (candidate.startsWith("setup/")) {
            val token = candidate.removePrefix("setup/")
            return if (SETUP_TOKEN_PATTERN.matches(token)) {
                "login?setupToken=${java.net.URLEncoder.encode(token, "UTF-8")}"
            } else {
                null // invalid token — silent fallback
            }
        }

        return if (candidate in routes) candidate else null
    }

    /**
     * Extracts and validates a raw setup token string.
     * Returns non-null only when [token] satisfies [SETUP_TOKEN_PATTERN].
     * Used by MainActivity to validate tokens extracted from HTTPS App Link URIs
     * before publishing the route.
     */
    fun validateSetupToken(token: String?): String? {
        if (token.isNullOrBlank()) return null
        return if (SETUP_TOKEN_PATTERN.matches(token)) token else null
    }
}
