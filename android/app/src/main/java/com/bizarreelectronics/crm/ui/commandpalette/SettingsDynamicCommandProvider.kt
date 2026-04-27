package com.bizarreelectronics.crm.ui.commandpalette

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PhoneAndroid
import androidx.compose.material.icons.filled.Security
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Storage
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import javax.inject.Inject

/**
 * §54.2 — Dynamic command provider that exposes Settings destinations in the
 * command palette so users can jump to any settings sub-screen by name.
 *
 * Each [Command] maps directly to a nav route registered in [AppNavGraph].
 * New settings screens should be added here alongside their nav registration.
 *
 * Injected via Hilt multibinding (`@IntoSet`) so [CommandPaletteModule] and
 * existing bindings are unaffected.
 */
class SettingsDynamicCommandProvider @Inject constructor(
    private val authPreferences: AuthPreferences,
) : DynamicCommandProvider {

    override fun provide(): List<Command> = buildList {
        // ── Profile / Account ──────────────────────────────────────────────
        add(
            Command(
                id = "settings:profile",
                label = "Settings → Profile",
                group = CommandGroup.ACTIONS,
                icon = Icons.Default.Person,
                keywords = listOf("profile", "account", "username", "avatar"),
                route = "settings/profile",
            ),
        )

        // ── Security ──────────────────────────────────────────────────────
        add(
            Command(
                id = "settings:security",
                label = "Settings → Security",
                group = CommandGroup.ACTIONS,
                icon = Icons.Default.Security,
                keywords = listOf("security", "2fa", "mfa", "totp", "passkey", "sessions", "login"),
                route = "settings/security",
            ),
        )
        add(
            Command(
                id = "settings:active-sessions",
                label = "Settings → Active Sessions",
                group = CommandGroup.ACTIONS,
                icon = Icons.Default.Security,
                keywords = listOf("sessions", "devices", "logout", "revoke"),
                route = "settings/security/sessions",
                adminOnly = true,
            ),
        )
        add(
            Command(
                id = "settings:change-password",
                label = "Settings → Change Password",
                group = CommandGroup.ACTIONS,
                icon = Icons.Default.Security,
                keywords = listOf("password", "credentials", "reset"),
                route = "settings/change-password",
            ),
        )

        // ── Notifications ─────────────────────────────────────────────────
        add(
            Command(
                id = "settings:notifications",
                label = "Settings → Notifications",
                group = CommandGroup.ACTIONS,
                icon = Icons.Default.Notifications,
                keywords = listOf("notifications", "push", "alerts", "sms", "quiet hours"),
                route = "settings/notifications",
            ),
        )

        // ── Appearance / Display ──────────────────────────────────────────
        add(
            Command(
                id = "settings:appearance",
                label = "Settings → Appearance",
                group = CommandGroup.ACTIONS,
                icon = Icons.Default.Palette,
                keywords = listOf("appearance", "theme", "density", "font", "contrast", "dark mode", "accent"),
                route = "settings/appearance",
            ),
        )
        add(
            Command(
                id = "settings:display",
                label = "Settings → Display",
                group = CommandGroup.ACTIONS,
                icon = Icons.Default.PhoneAndroid,
                keywords = listOf("display", "screen", "queue board", "tv", "keep screen on"),
                route = "settings/display",
            ),
        )

        // ── Hardware ──────────────────────────────────────────────────────
        add(
            Command(
                id = "settings:hardware",
                label = "Settings → Hardware",
                group = CommandGroup.ACTIONS,
                icon = Icons.Default.Settings,
                keywords = listOf("hardware", "printer", "barcode", "scanner", "scale", "terminal"),
                route = "settings/hardware",
            ),
        )

        // ── Data / Storage ────────────────────────────────────────────────
        add(
            Command(
                id = "settings:data",
                label = "Settings → Data",
                group = CommandGroup.ACTIONS,
                icon = Icons.Default.Storage,
                keywords = listOf("data", "import", "export", "backup", "cache", "reset"),
                route = "settings/data",
            ),
        )

        // ── Admin-only settings ────────────────────────────────────────────
        val isAdmin = authPreferences.userRole == "admin"
        if (isAdmin) {
            add(
                Command(
                    id = "settings:integrations",
                    label = "Settings → Integrations",
                    group = CommandGroup.ACTIONS,
                    icon = Icons.Default.Settings,
                    keywords = listOf("integrations", "zapier", "webhook", "blockhyp", "google wallet"),
                    route = "settings/integrations",
                    adminOnly = true,
                ),
            )
            add(
                Command(
                    id = "settings:team",
                    label = "Settings → Team & Roles",
                    group = CommandGroup.ACTIONS,
                    icon = Icons.Default.Person,
                    keywords = listOf("team", "roles", "staff", "employees", "permissions"),
                    route = "settings/team",
                    adminOnly = true,
                ),
            )
            add(
                Command(
                    id = "settings:diagnostics",
                    label = "Settings → Diagnostics",
                    group = CommandGroup.ACTIONS,
                    icon = Icons.Default.Settings,
                    keywords = listOf("diagnostics", "debug", "logs", "server", "version", "force sync"),
                    route = "settings/full-diagnostics",
                    adminOnly = true,
                ),
            )
        }
    }
}
