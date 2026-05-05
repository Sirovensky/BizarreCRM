package com.bizarreelectronics.crm.util

import android.os.StrictMode
import com.bizarreelectronics.crm.BuildConfig
import timber.log.Timber

/**
 * L2505 — StrictMode initialiser.
 *
 * Enables [StrictMode] in debug builds only, catching:
 *   - **Thread policy violations**: disk reads/writes on the main thread,
 *     network calls on the main thread, slow calls, and custom slow calls.
 *   - **VM policy violations**: activity leaks, cursor leaks, closeable leaks,
 *     content URI access without permission, untagged sockets, file URI exposure,
 *     and cleartext network traffic.
 *
 * All violations are logged via [StrictMode.ThreadPolicy.Builder.penaltyLog] and
 * [StrictMode.VmPolicy.Builder.penaltyLog] so they surface in Logcat without
 * crashing the app (penaltyDeath is not used — it would disrupt manual QA flows).
 *
 * In release builds this function is a **no-op** — the guard is [BuildConfig.DEBUG].
 *
 * ## Usage
 * Call once from [com.bizarreelectronics.crm.BizarreCrmApp.onCreate]:
 * ```kotlin
 * StrictModeInit.init()
 * ```
 *
 * ## Note on false positives
 * Some third-party libraries (e.g. EncryptedSharedPreferences, WorkManager
 * initialisation) trigger thread-policy violations on their first call.  These
 * are logged but should be investigated rather than suppressed — the goal is
 * to catch app-owned code doing I/O on the main thread.
 */
object StrictModeInit {

    private const val TAG = "StrictModeInit"

    /**
     * Installs [StrictMode] thread and VM policies in [BuildConfig.DEBUG] builds.
     *
     * Safe to call multiple times — StrictMode replaces its global policies, so
     * calling this more than once simply resets to the same configuration.
     */
    fun init() {
        if (!BuildConfig.DEBUG) return

        StrictMode.setThreadPolicy(
            StrictMode.ThreadPolicy.Builder()
                .detectAll()
                .penaltyLog()
                .build(),
        )

        StrictMode.setVmPolicy(
            StrictMode.VmPolicy.Builder()
                .detectAll()
                .penaltyLog()
                .build(),
        )

        Timber.tag(TAG).d("StrictMode enabled (DEBUG build)")
    }
}
