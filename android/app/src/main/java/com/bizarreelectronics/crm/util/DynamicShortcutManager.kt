package com.bizarreelectronics.crm.util

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import com.bizarreelectronics.crm.MainActivity
import com.bizarreelectronics.crm.R

/**
 * §24.3 — Dynamic launcher shortcuts via [ShortcutManagerCompat].
 *
 * Dynamic shortcuts complement the static entries in `res/xml/shortcuts.xml`:
 * - Static shortcuts (New Ticket, New Customer, Scan) are always visible.
 * - Dynamic shortcuts (Recent Customers) are updated at runtime based on data.
 *
 * ## Recent Customers (top 4 by last interaction)
 * Call [publishRecentCustomers] after any customer interaction (open customer
 * record, create ticket for customer, send SMS).  The method replaces all
 * dynamic shortcuts with the new list — the OS caps dynamic shortcuts at 5
 * but we stay at 4 to leave room for the static set.
 *
 * ## Pinned shortcuts
 * Call [requestPinShortcut] to let the user pin a specific customer's shortcut
 * to their launcher.  On launchers that support it, a system dialog asks for
 * confirmation.  [ShortcutManagerCompat.isRequestPinShortcutSupported] gates
 * the call so it's a no-op on unsupported launchers.
 *
 * ## Icon theming
 * Shortcuts use the app launcher icon ([R.mipmap.ic_launcher]) as a placeholder.
 * When adaptive-icon per-shortcut artwork is available, replace the
 * [IconCompat.createWithResource] call with [IconCompat.createWithAdaptiveBitmap]
 * for per-customer initials icons (see §24.3 "Icon per shortcut; theme-aware
 * variant").
 */
object DynamicShortcutManager {

    /**
     * Data class representing a recent customer to surface as a dynamic shortcut.
     *
     * @param customerId  Server-side customer ID used in the deep-link URI.
     * @param displayName Full name shown as the shortcut label.
     */
    data class RecentCustomer(
        val customerId: Int,
        val displayName: String,
    )

    /**
     * Replaces all dynamic shortcuts with up to [MAX_RECENT] recent customers.
     *
     * Safe to call on any thread — [ShortcutManagerCompat] is thread-safe.
     *
     * @param context  Application context.
     * @param customers Ordered list of recent customers; only the first [MAX_RECENT]
     *                  entries are used.
     */
    fun publishRecentCustomers(context: Context, customers: List<RecentCustomer>) {
        val shortcuts = customers
            .take(MAX_RECENT)
            .mapIndexed { index, customer ->
                val deepLink = Uri.parse("bizarrecrm://customer/${customer.customerId}")
                val intent = Intent(context, MainActivity::class.java).apply {
                    action = Intent.ACTION_VIEW
                    data = deepLink
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                }
                ShortcutInfoCompat.Builder(context, "recent_customer_${customer.customerId}")
                    .setShortLabel(customer.displayName.take(MAX_LABEL_LEN))
                    .setLongLabel(customer.displayName)
                    .setIcon(IconCompat.createWithResource(context, R.mipmap.ic_launcher))
                    .setIntent(intent)
                    .setRank(index)
                    .build()
            }

        runCatching {
            ShortcutManagerCompat.setDynamicShortcuts(context, shortcuts)
        }.onFailure { e ->
            android.util.Log.w(TAG, "setDynamicShortcuts failed: ${e.message}")
        }
    }

    /**
     * Attempts to pin a shortcut for [customer] on launchers that support it.
     *
     * Shows a system-provided confirmation dialog on supported launchers
     * (Pixel Launcher, AOSP launcher, etc.).  On unsupported launchers this
     * is a silent no-op — do NOT show your own error UI.
     *
     * @param context  Activity or application context.
     * @param customer The customer to pin.
     */
    fun requestPinShortcut(context: Context, customer: RecentCustomer) {
        if (!ShortcutManagerCompat.isRequestPinShortcutSupported(context)) return

        val deepLink = Uri.parse("bizarrecrm://customer/${customer.customerId}")
        val intent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            data = deepLink
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val shortcut = ShortcutInfoCompat.Builder(context, "pinned_customer_${customer.customerId}")
            .setShortLabel(customer.displayName.take(MAX_LABEL_LEN))
            .setLongLabel(customer.displayName)
            .setIcon(IconCompat.createWithResource(context, R.mipmap.ic_launcher))
            .setIntent(intent)
            .build()

        runCatching {
            ShortcutManagerCompat.requestPinShortcut(context, shortcut, null)
        }.onFailure { e ->
            android.util.Log.w(TAG, "requestPinShortcut failed: ${e.message}")
        }
    }

    /**
     * Removes all dynamic shortcuts previously set by [publishRecentCustomers].
     * Call on logout to clear stale customer data from the launcher.
     */
    fun clearDynamicShortcuts(context: Context) {
        runCatching {
            ShortcutManagerCompat.removeAllDynamicShortcuts(context)
        }
    }

    private const val TAG = "DynamicShortcutManager"

    /** Android OS cap for dynamic shortcuts is 5; we use 4 to keep room for static set. */
    private const val MAX_RECENT = 4

    /** Maximum characters for shortcut short label per OS constraint. */
    private const val MAX_LABEL_LEN = 25
}
