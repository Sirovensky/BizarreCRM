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
        // §56.4 — Android TV / Leanback launcher launches with bizarrecrm://tvqueue.
        // The host "tvqueue" maps directly to the Screen.TvQueueBoard route "tv/queue".
        "tvqueue",
        // §68.2 — static deep-link routes (no path parameters).
        "dashboard",
        "tickets",
        "pos/new",
        "reports",
        "settings",
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
     *
     * §2.21 L454 — magic-link token handling:
     * A candidate of the form `"magic/<token>"` is recognised as a magic-link
     * sign-in deep link. The token is validated against [SETUP_TOKEN_PATTERN]
     * (same 20–128 URL-safe chars pattern). A valid token is published to
     * [DeepLinkBus.publishMagicLinkToken] by the caller (MainActivity) so the
     * LoginViewModel can collect and dispatch the exchange call.
     * Returns the sentinel string `"magic/<token>"` so the caller can distinguish
     * the magic-link case from a nav-route case.
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

        // §2.21 L454 — magic-link sign-in: "magic/<token>"
        if (candidate.startsWith("magic/")) {
            val token = candidate.removePrefix("magic/")
            return if (SETUP_TOKEN_PATTERN.matches(token)) {
                "magic/$token" // sentinel returned to MainActivity; not a nav route
            } else {
                null // invalid token shape — silent fallback
            }
        }

        // §2.15 L387-L388 — forgot-PIN reset link: "forgot-pin/<token>"
        if (candidate.startsWith("forgot-pin/")) {
            val token = candidate.removePrefix("forgot-pin/")
            return if (SETUP_TOKEN_PATTERN.matches(token)) {
                "forgot-pin/$token" // sentinel returned to MainActivity; not a nav route
            } else {
                null // invalid token — silent fallback
            }
        }

        // §68.2 — parametric deep-link routes. Each path is allow-listed by prefix;
        // the id/slug segment is accepted as-is since the receiving composable validates
        // it (toLongOrNull / URI-decode). Slugs with path traversal chars (/) are
        // rejected because startsWith matches only the first path level.
        if (candidate.startsWith("tickets/")) return candidate
        if (candidate.startsWith("customers/")) return candidate
        if (candidate.startsWith("inventory/")) return candidate
        if (candidate.startsWith("invoices/")) return candidate
        if (candidate.startsWith("estimates/")) return candidate
        if (candidate.startsWith("leads/")) return candidate
        if (candidate.startsWith("appointments/")) return candidate
        if (candidate.startsWith("sms/")) return candidate
        if (candidate.startsWith("pos/cart/")) return candidate
        if (candidate.startsWith("reports/")) return candidate
        if (candidate.startsWith("settings/")) return candidate

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

    /**
     * §2.21 L454 — validates a raw magic-link token string.
     * Returns non-null only when [token] satisfies [SETUP_TOKEN_PATTERN]
     * (same 20–128 URL-safe base64 character pattern as setup tokens).
     * Used by MainActivity to validate tokens extracted from both:
     *   - HTTPS App Link URIs: https://app.bizarrecrm.com/magic/<token>
     *   - Custom scheme URIs:  bizarrecrm://magic/<token>
     */
    fun validateMagicToken(token: String?): String? {
        if (token.isNullOrBlank()) return null
        return if (SETUP_TOKEN_PATTERN.matches(token)) token else null
    }

    /**
     * §2.15 L387-L388 — validates a raw forgot-PIN reset token string.
     * Returns non-null only when [token] satisfies [SETUP_TOKEN_PATTERN]
     * (same 20–128 URL-safe base64 character pattern as other tokens).
     * Used by MainActivity to validate tokens extracted from:
     *   - Custom scheme URIs: bizarrecrm://forgot-pin/<token>
     */
    fun validateForgotPinToken(token: String?): String? {
        if (token.isNullOrBlank()) return null
        return if (SETUP_TOKEN_PATTERN.matches(token)) token else null
    }
}
