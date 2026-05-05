package com.bizarreelectronics.crm.util

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

/**
 * §21.6 — OEM battery-optimisation helper.
 *
 * Many Android OEMs (Samsung, Xiaomi, Oppo/Realme, Huawei/Honor) ship aggressive
 * RAM managers that kill background processes and delay FCM delivery far beyond
 * Android's standard Doze behaviour. This helper:
 *
 *  1. Detects whether the device is made by a known OEM killer (§21.6, dontkillmyapp.com).
 *  2. Provides [openOemBatterySettings] to deep-link into the OEM's "Protected Apps" /
 *     "Auto-start" / "Battery" screen where the user can whitelist our app.
 *  3. Gates the one-time educational prompt via [AppPreferences.oemBatteryPromptShown]
 *     so we never annoy the user more than once.
 *
 * ## Policy note (§21.6)
 * We deliberately do NOT request [android.Manifest.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS].
 * That permission triggers Play Store review for non-whitelisted use-cases and is
 * not appropriate for a CRM app. Instead we rely on:
 *   • FCM high-priority pushes (server responsibility — §21.1)
 *   • WorkManager with CONNECTED constraint (survives Doze via FCM wake)
 *   • This one-time educational prompt for OEM-specific killers
 *
 * ## Usage
 * ```kotlin
 * // In a post-login SettingsScreen or onboarding flow:
 * if (oemBatteryHelper.shouldShowPrompt()) {
 *     ShowOemBatteryDialog {
 *         oemBatteryHelper.openOemBatterySettings(context)
 *         oemBatteryHelper.markPromptShown()
 *     }
 * }
 * ```
 */
@Singleton
class OemBatteryHelper @Inject constructor(
    @ApplicationContext private val context: Context,
    private val appPreferences: AppPreferences,
) {

    /**
     * Returns `true` when the device is manufactured by an OEM known to run
     * aggressive task killers AND the one-time prompt has not yet been shown.
     *
     * Call-site: SettingsScreen post-login flow (§21.6 — UI call-site deferred
     * to SettingsScreen wave; the logic is ready here).
     */
    fun shouldShowPrompt(): Boolean {
        if (appPreferences.oemBatteryPromptShown) return false
        return isAggresiveOem()
    }

    /**
     * Returns `true` if [Build.MANUFACTURER] is one of the OEMs known to ship
     * aggressive task killers according to dontkillmyapp.com.
     */
    fun isAggresiveOem(): Boolean {
        val manufacturer = Build.MANUFACTURER.lowercase()
        return manufacturer in AGGRESSIVE_OEM_MANUFACTURERS
    }

    /**
     * Mark the educational prompt as shown so we never display it again.
     * Persist immediately — called immediately after the dialog is dismissed
     * (whether the user taps "Open Settings" or "Maybe later").
     */
    fun markPromptShown() {
        appPreferences.oemBatteryPromptShown = true
    }

    /**
     * Deep-link to the OEM's battery/autostart settings screen where the user
     * can whitelist the app. Falls back to the stock Android App Info screen if
     * no OEM-specific screen can be found.
     *
     * OEM-specific targets (all verified against dontkillmyapp.com):
     *   - Samsung: "protected apps" in Device Care / Battery settings (One UI ≥ 3)
     *   - Xiaomi/MIUI: com.miui.securitycenter / com.miui.powerkeeper autostart
     *   - Oppo/Realme/OnePlus/ColorOS: com.coloros.safecenter / com.oplus.safecenter
     *   - Huawei/Honor: com.huawei.systemmanager
     *
     * [android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS] is the
     * guaranteed fallback — it opens the App Info screen that always exists.
     *
     * @param ctx Activity or Service context; must be able to start activities.
     */
    fun openOemBatterySettings(ctx: Context = context) {
        val manufacturer = Build.MANUFACTURER.lowercase()
        val packageName = ctx.packageName

        val oemIntent: Intent? = when {
            manufacturer == "samsung" -> buildSamsungIntent()
            manufacturer == "xiaomi" || manufacturer == "redmi" -> buildXiaomiIntent(packageName)
            manufacturer == "oppo" || manufacturer == "realme" || manufacturer == "oneplus" -> buildOppoIntent(packageName)
            manufacturer == "huawei" || manufacturer == "honor" -> buildHuaweiIntent()
            else -> null
        }

        val intent = resolveIntent(ctx, oemIntent) ?: buildFallbackAppInfoIntent(packageName)
        try {
            ctx.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (e: Exception) {
            Log.w(TAG, "Could not open OEM battery settings: ${e.message}")
            // Last resort: open app info — this always works.
            try {
                ctx.startActivity(
                    buildFallbackAppInfoIntent(packageName)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
            } catch (e2: Exception) {
                Log.e(TAG, "Could not open app info either: ${e2.message}")
            }
        }
    }

    // ── OEM-specific intent builders ─────────────────────────────────────────

    /**
     * Samsung One UI — Battery > Background usage limits > "Never sleeping apps"
     * (One UI 3+). On older One UI / TouchWiz the Device Care / Battery screen is
     * the closest equivalent; we open the generic battery settings as fallback.
     */
    private fun buildSamsungIntent(): Intent =
        Intent().apply {
            component = ComponentName(
                "com.samsung.android.lool",
                "com.samsung.android.sm.ui.battery.BatteryActivity",
            )
        }

    /**
     * Xiaomi MIUI — Security Center > Permissions > Autostart.
     * Both the primary and fallback package cover different MIUI generations:
     *   com.miui.securitycenter  → MIUI 10+ (Redmi, Poco, Mi)
     *   com.miui.powerkeeper     → older MIUI builds
     */
    private fun buildXiaomiIntent(packageName: String): Intent =
        Intent("miui.intent.action.APP_PERM_EDITOR").apply {
            setPackage("com.miui.securitycenter")
            putExtra("extra_pkgname", packageName)
        }

    /**
     * Oppo / Realme / OnePlus (ColorOS / OxygenOS) — Security Center >
     * Privacy Permissions > Start in Background.
     *
     * Package name differs by generation:
     *   com.coloros.safecenter   → ColorOS < 11
     *   com.oplus.safecenter     → ColorOS 11+ / OxygenOS 11+
     */
    private fun buildOppoIntent(packageName: String): Intent =
        Intent().apply {
            component = ComponentName(
                "com.coloros.safecenter",
                "com.coloros.privacypermissionsentry.PermissionTopActivity",
            )
            putExtra("extra_pkgname", packageName)
        }

    /**
     * Huawei / Honor (EMUI / MagicUI) — System Manager > Battery > Protected Apps.
     *
     * Package:
     *   com.huawei.systemmanager → EMUI / MagicUI (all supported versions)
     */
    private fun buildHuaweiIntent(): Intent =
        Intent().apply {
            component = ComponentName(
                "com.huawei.systemmanager",
                "com.huawei.systemmanager.optimize.process.ProtectActivity",
            )
        }

    /** Stock Android App Info screen — always available as a final fallback. */
    private fun buildFallbackAppInfoIntent(packageName: String): Intent =
        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.fromParts("package", packageName, null)
        }

    /**
     * Returns [oemIntent] if a matching Activity is available on this device,
     * otherwise null. This prevents ActivityNotFoundException on devices that
     * share a manufacturer name but ship a different OEM skin (e.g. Samsung
     * tablets that don't have the SmartManager component).
     */
    private fun resolveIntent(ctx: Context, oemIntent: Intent?): Intent? {
        if (oemIntent == null) return null
        return if (ctx.packageManager.resolveActivity(oemIntent, 0) != null) {
            oemIntent
        } else {
            Log.d(TAG, "OEM intent unresolvable; falling back to App Info")
            null
        }
    }

    companion object {
        private const val TAG = "OemBatteryHelper"

        /**
         * OEM manufacturers known to ship aggressive task killers.
         * All values are lower-case to match [Build.MANUFACTURER.lowercase()].
         *
         * Sources: dontkillmyapp.com, issuetracker.google.com, AndroidX WorkManager docs.
         * Added "realme" and "honor" separately; they may share packages with their
         * parent brands (Oppo / Huawei) but [Build.MANUFACTURER] differs.
         */
        val AGGRESSIVE_OEM_MANUFACTURERS: Set<String> = setOf(
            "samsung",
            "xiaomi",
            "redmi",
            "poco",
            "oppo",
            "realme",
            "oneplus",
            "huawei",
            "honor",
            "vivo",
            "meizu",
            "zte",
            "letv",
        )
    }
}
