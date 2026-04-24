package com.bizarreelectronics.crm.ui.screens.settings

/**
 * L1976/L1978 — Static searchable index for Settings entries.
 *
 * Each [SettingsEntry] carries a [route] that matches a Screen in AppNavGraph,
 * so tapping a search result navigates directly to the relevant sub-screen.
 * The [keywords] list is lowercased; search normalises the query before matching.
 *
 * Deep-link scheme: `bizarrecrm://settings/<id>` maps to the [route] field
 * via [SettingsMetadata.findById]. AppNavGraph handles the deep-link intent
 * by calling [findById] and navigating to the resolved route.
 */
data class SettingsEntry(
    val id: String,
    val title: String,
    val description: String,
    val keywords: List<String>,
    val route: String,
)

object SettingsMetadata {

    val entries: List<SettingsEntry> = listOf(
        SettingsEntry(
            id = "profile",
            title = "Edit Profile",
            description = "Change your name, avatar, password, and PIN",
            keywords = listOf("profile", "name", "avatar", "photo", "password", "pin", "account"),
            route = "settings/profile",
        ),
        SettingsEntry(
            id = "notifications",
            title = "Notifications",
            description = "Configure push, SMS, email alerts and quiet hours",
            keywords = listOf("notifications", "push", "sms", "email", "alerts", "quiet hours", "sound", "ringtone"),
            route = "settings/notifications",
        ),
        SettingsEntry(
            id = "appearance",
            title = "Appearance",
            description = "Dashboard density, accent color, font scale, high contrast",
            keywords = listOf("appearance", "density", "color", "accent", "font", "scale", "contrast", "theme", "dark mode"),
            route = "settings/appearance",
        ),
        SettingsEntry(
            id = "language",
            title = "Language & Region",
            description = "Language, timezone, date format, currency",
            keywords = listOf("language", "region", "timezone", "time zone", "date", "currency", "locale"),
            route = "settings/language",
        ),
        SettingsEntry(
            id = "security",
            title = "Security",
            description = "Biometric unlock, PIN, 2FA, sessions, screenshot blocking",
            keywords = listOf("security", "biometric", "pin", "2fa", "two factor", "sessions", "screenshot", "password"),
            route = "settings/security",
        ),
        SettingsEntry(
            id = "security-summary",
            title = "Security Summary",
            description = "Overview of 2FA, passkeys, recovery codes, SSO, and sessions",
            keywords = listOf("security", "summary", "2fa", "passkey", "recovery", "sso", "sessions", "screenshot"),
            route = "settings/security/summary",
        ),
        SettingsEntry(
            id = "display",
            title = "Display",
            description = "TV queue board, keep screen on",
            keywords = listOf("display", "screen", "tv", "queue", "board", "kiosk"),
            route = "settings/display",
        ),
        SettingsEntry(
            id = "hardware",
            title = "Hardware",
            description = "Printers, payment terminal, barcode scanner",
            keywords = listOf("hardware", "printer", "terminal", "barcode", "scanner", "payment"),
            route = "settings/hardware",
        ),
        SettingsEntry(
            id = "shared-device",
            title = "Shared Device Mode",
            description = "Counter kiosk mode with staff switching",
            keywords = listOf("shared", "device", "kiosk", "counter", "staff", "switch"),
            route = "settings/shared-device",
        ),
        SettingsEntry(
            id = "theme",
            title = "Theme",
            description = "Light, dark, or system theme and dynamic color",
            keywords = listOf("theme", "dark", "light", "dynamic", "color", "material you"),
            route = "settings/theme",
        ),
    )

    /** Lookup by [id]. Used by the deep-link resolver. */
    fun findById(id: String): SettingsEntry? = entries.firstOrNull { it.id == id }

    /**
     * Filter entries by [query] (case-insensitive).
     * Matches against title, description, and any keyword.
     */
    fun search(query: String): List<SettingsEntry> {
        if (query.isBlank()) return entries
        val q = query.trim().lowercase()
        return entries.filter { entry ->
            entry.title.lowercase().contains(q) ||
                entry.description.lowercase().contains(q) ||
                entry.keywords.any { it.contains(q) }
        }
    }
}
