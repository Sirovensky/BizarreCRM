package com.bizarreelectronics.crm.ui.theme

import androidx.compose.runtime.compositionLocalOf
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.util.WindowMode

/**
 * §3.19 L613–L616 — Dashboard density mode.
 *
 * Three levels allow the user to trade visual breathing room for information density:
 *
 * | Mode        | KPI columns (phone/tablet) | Base spacing | Type scale |
 * |-------------|---------------------------|--------------|------------|
 * | Comfortable | 1 / 2                     | 16 dp        | 1.00       |
 * | Cozy        | 2 / 3                     | 12 dp        | 0.95       |
 * | Compact     | 3 / 4                     | 8 dp         | 0.90       |
 *
 * **Shared-device gate**: when `sharedDeviceModeEnabled = true` (commit 8714066)
 * the density setting is ignored — the dashboard always renders in [Comfortable]
 * mode regardless of the persisted preference. This keeps the counter-kiosk view
 * predictable for all staff members sharing the device.
 *
 * **Compact mode note**: [Compact] is intended for power users and large screens.
 * On small phones (< 360 dp) Compact may clip content; the default for new
 * installs on phone form-factors is therefore [Comfortable].
 */
enum class DashboardDensity {

    /**
     * Default mode — generous spacing, one KPI column on phones.
     * Suits all screen sizes and new users.
     */
    Comfortable,

    /**
     * Balanced mode — moderate spacing, two KPI columns on phones.
     * Default for tablet form-factors on a fresh install.
     */
    Cozy,

    /**
     * High-density mode — tight spacing, three KPI columns on phones.
     *
     * **Intended for power users and large screens only.** On small phones
     * (< 360 dp logical width) some card content may appear cramped.
     */
    Compact;

    /**
     * Returns the number of KPI grid columns appropriate for [windowMode].
     *
     * | Density     | Phone | Tablet | Desktop |
     * |-------------|-------|--------|---------|
     * | Comfortable | 1     | 2      | 2       |
     * | Cozy        | 2     | 3      | 3       |
     * | Compact     | 3     | 4      | 4       |
     */
    fun columnsForWindowSize(windowMode: WindowMode): Int = when (this) {
        Comfortable -> if (windowMode == WindowMode.Phone) 1 else 2
        Cozy        -> if (windowMode == WindowMode.Phone) 2 else 3
        Compact     -> if (windowMode == WindowMode.Phone) 3 else 4
    }

    /**
     * Base spacing used between grid items and section padding.
     *
     * 16 dp (Comfortable) → 12 dp (Cozy) → 8 dp (Compact).
     */
    val baseSpacing: Dp
        get() = when (this) {
            Comfortable -> 16.dp
            Cozy        -> 12.dp
            Compact     -> 8.dp
        }

    /**
     * Relative text scale factor. Applied via `TextStyle.fontSize * typeScale`
     * or via `Modifier.scale` on type nodes where Compose typography scaling
     * is not available.
     *
     * 1.00 (Comfortable) → 0.95 (Cozy) → 0.90 (Compact).
     *
     * Note: this is intentionally orthogonal to the M3 Typography definitions
     * — do NOT override Theme.typography here; apply at the call site only
     * where information density is the goal (e.g. KPI value labels).
     */
    val typeScale: Float
        get() = when (this) {
            Comfortable -> 1.00f
            Cozy        -> 0.95f
            Compact     -> 0.90f
        }

    companion object {
        /**
         * Deserialise from the persisted preference string.
         * Returns [Comfortable] for any unrecognised value so a fresh install
         * or a future renamed key never leaves the UI in a broken state.
         */
        fun fromKey(key: String): DashboardDensity = when (key) {
            "cozy"    -> Cozy
            "compact" -> Compact
            else      -> Comfortable // "comfortable" + fallback
        }

        /** Serialise to the preference key string. */
        fun DashboardDensity.toKey(): String = when (this) {
            Comfortable -> "comfortable"
            Cozy        -> "cozy"
            Compact     -> "compact"
        }
    }
}

/**
 * [CompositionLocal] that propagates the active [DashboardDensity] through the
 * Compose tree. Defaults to [DashboardDensity.Comfortable] so any composable
 * that reads it without an explicit provider still gets a safe, predictable value.
 *
 * Provide at the [MainActivity] level via [CompositionLocalProvider]:
 * ```kotlin
 * CompositionLocalProvider(LocalDashboardDensity provides density) {
 *     // … your content
 * }
 * ```
 */
val LocalDashboardDensity = compositionLocalOf { DashboardDensity.Comfortable }
