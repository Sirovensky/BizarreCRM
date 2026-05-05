package com.bizarreelectronics.crm.util

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.net.Uri
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import com.bizarreelectronics.crm.MainActivity

/**
 * §14.10 — Context-aware launcher App Shortcut for the clock-in / clock-out action.
 *
 * Android launchers show static shortcuts from `res/xml/shortcuts.xml` on a
 * long-press of the app icon. This utility adds a **dynamic** shortcut on top
 * that reflects the employee's *current* shift state:
 *
 * - **Clocked out** — shortcut label "Clock in", icon shows a clock with a
 *   right-pointing "play" indicator (cream on brand-dark background).
 * - **Clocked in**  — shortcut label "Clock out", icon shows a clock with a
 *   stop-square indicator.
 *
 * The shortcut is assigned rank 0 so it floats to the top of the dynamic set.
 * It deep-links to `bizarrecrm://clockin` which the NavGraph resolves to
 * [com.bizarreelectronics.crm.ui.screens.employees.ClockInOutScreen].
 *
 * ## Call sites
 * Call [updateShortcut] from every place that changes the clock state:
 *  - `ClockInOutViewModel.broadcastClockState()`
 *  - `ClockInGlanceWidget` (on widget interaction — not yet wired)
 *
 * ## Lifecycle
 * Dynamic shortcuts survive app updates but are cleared on uninstall.
 * [clearShortcut] should be called on logout to avoid showing a stale action.
 *
 * ## Threading
 * [ShortcutManagerCompat] is thread-safe; this object can be called from any
 * dispatcher including `Dispatchers.IO`.
 */
object ClockShortcutPublisher {

    /** Stable shortcut ID used to replace (not add) the shortcut on every update. */
    private const val SHORTCUT_ID = "dynamic_clock_in_out"

    /** Deep-link URI handled by `AppNavGraph` route `Screen.ClockInOut`. */
    private const val DEEP_LINK_URI = "bizarrecrm://clockin"

    /** Maximum short-label length enforced by the Android launcher contract. */
    private const val MAX_SHORT_LABEL = 25

    /**
     * Publishes (or replaces) the clock dynamic shortcut.
     *
     * Safe to call on any thread. A failed [ShortcutManagerCompat] call is
     * logged and swallowed — shortcut updates are best-effort UI sugar.
     *
     * @param context     Application context.
     * @param isClockedIn `true` → show "Clock out"; `false` → show "Clock in".
     */
    fun updateShortcut(context: Context, isClockedIn: Boolean) {
        val shortLabel: String
        val longLabel: String
        val icon: IconCompat

        if (isClockedIn) {
            shortLabel = context.getString(
                com.bizarreelectronics.crm.R.string.shortcut_clock_out_short
            ).take(MAX_SHORT_LABEL)
            longLabel = context.getString(
                com.bizarreelectronics.crm.R.string.shortcut_clock_out_long
            )
            icon = buildClockOutIcon()
        } else {
            shortLabel = context.getString(
                com.bizarreelectronics.crm.R.string.shortcut_clock_in_short
            ).take(MAX_SHORT_LABEL)
            longLabel = context.getString(
                com.bizarreelectronics.crm.R.string.shortcut_clock_in_long
            )
            icon = buildClockInIcon()
        }

        val intent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            data = Uri.parse(DEEP_LINK_URI)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }

        val shortcut = ShortcutInfoCompat.Builder(context, SHORTCUT_ID)
            .setShortLabel(shortLabel)
            .setLongLabel(longLabel)
            .setIcon(icon)
            .setIntent(intent)
            .setRank(0) // float above recent-customers dynamic shortcuts (rank 1–4)
            .build()

        runCatching {
            // updateShortcuts replaces existing shortcuts with matching IDs.
            // If the shortcut is new, setDynamicShortcuts would clobber others;
            // use pushDynamicShortcut (API 25+) to upsert without disturbing others.
            ShortcutManagerCompat.pushDynamicShortcut(context, shortcut)
        }.onFailure { e ->
            android.util.Log.w(TAG, "updateShortcut failed: ${e.message}")
        }
    }

    /**
     * Removes the clock dynamic shortcut. Call on logout so the launcher does
     * not show a stale "Clock in" action when no session is active.
     *
     * @param context Application context.
     */
    fun clearShortcut(context: Context) {
        runCatching {
            ShortcutManagerCompat.removeDynamicShortcuts(context, listOf(SHORTCUT_ID))
        }.onFailure { e ->
            android.util.Log.w(TAG, "clearShortcut failed: ${e.message}")
        }
    }

    // -------------------------------------------------------------------------
    // Icon builders — programmatic 192×192 px bitmaps
    // -------------------------------------------------------------------------

    /**
     * Clock icon with a right-pointing triangle (play) badge in the lower-right
     * quadrant to indicate "start / clock in".
     * Brand scheme: #121017 background, #FDEED0 clock ring + badge.
     */
    private fun buildClockInIcon(): IconCompat {
        val bmp = buildClockBase()
        val canvas = Canvas(bmp)
        val size = ICON_PX.toFloat()
        val cx = size / 2f
        val cy = size / 2f

        // Play-triangle badge — lower-right quadrant
        val badgePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#FDEED0")
            style = Paint.Style.FILL
        }
        // Triangle pointing right: tip at (cx+30, cy+30), base from (cx+12, cy+18) to (cx+12, cy+42)
        val path = android.graphics.Path().apply {
            moveTo(cx + 30f, cy + 30f)
            lineTo(cx + 12f, cy + 18f)
            lineTo(cx + 12f, cy + 42f)
            close()
        }
        canvas.drawPath(path, badgePaint)

        return IconCompat.createWithBitmap(bmp)
    }

    /**
     * Clock icon with a filled stop-square badge in the lower-right quadrant
     * to indicate "stop / clock out".
     * Brand scheme: #121017 background, #FDEED0 clock ring + badge.
     */
    private fun buildClockOutIcon(): IconCompat {
        val bmp = buildClockBase()
        val canvas = Canvas(bmp)
        val size = ICON_PX.toFloat()
        val cx = size / 2f
        val cy = size / 2f

        // Stop-square badge — lower-right quadrant
        val badgePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#FDEED0")
            style = Paint.Style.FILL
        }
        val squareLeft  = cx + 12f
        val squareTop   = cy + 18f
        val squareRight = cx + 30f
        val squareBottom = cy + 36f
        canvas.drawRoundRect(
            RectF(squareLeft, squareTop, squareRight, squareBottom),
            4f, 4f, badgePaint
        )

        return IconCompat.createWithBitmap(bmp)
    }

    /**
     * Renders the shared clock-face base: brand-dark background circle,
     * cream clock-ring, hour + minute hands, and centre dot.
     * Returns a mutable [Bitmap] so callers can draw badges on top.
     */
    private fun buildClockBase(): Bitmap {
        val size = ICON_PX
        val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        val s = size.toFloat()
        val cx = s / 2f
        val cy = s / 2f

        // Brand-dark background circle
        val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#121017")
            style = Paint.Style.FILL
        }
        canvas.drawCircle(cx, cy, cx, bgPaint)

        // Cream clock ring (annulus via two circles)
        val ringPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#FDEED0")
            style = Paint.Style.STROKE
            strokeWidth = s * 0.04f
        }
        canvas.drawCircle(cx, cy, s * 0.26f, ringPaint)

        val handPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#FDEED0")
            style = Paint.Style.STROKE
            strokeWidth = s * 0.03f
            strokeCap = Paint.Cap.ROUND
        }
        // Hour hand — pointing to 9 (left)
        canvas.drawLine(cx, cy, cx - s * 0.18f, cy, handPaint)
        // Minute hand — pointing to 12 (up)
        canvas.drawLine(cx, cy, cx, cy - s * 0.22f, handPaint)

        // Centre dot
        val dotPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#FDEED0")
            style = Paint.Style.FILL
        }
        canvas.drawCircle(cx, cy, s * 0.025f, dotPaint)

        return bmp
    }

    private const val TAG = "ClockShortcutPublisher"

    /** Bitmap pixel size — renders crisply across all screen densities. */
    private const val ICON_PX = 192
}
