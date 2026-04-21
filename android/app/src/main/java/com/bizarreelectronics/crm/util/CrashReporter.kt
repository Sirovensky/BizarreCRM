package com.bizarreelectronics.crm.util

import android.content.Context
import android.os.Build
import android.util.Log
import com.bizarreelectronics.crm.BuildConfig
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import javax.inject.Inject
import javax.inject.Singleton

/**
 * §32.3 — last-resort crash reporter.
 *
 * Wraps [Thread.setDefaultUncaughtExceptionHandler] so that an uncaught
 * exception lands in `app private storage / crash-reports/<timestamp>.log`
 * before the OS shows the "App keeps stopping" dialog.
 *
 * Sovereignty (per §1 / §28.7): we **never** ship crash data to a third
 * party. The current implementation writes locally only. A future
 * iteration uploads the file to the tenant's own server when an endpoint
 * exists (see §32.2 TelemetryClient TODO). Until then the file is purely a
 * developer aid recoverable via `adb pull` + Settings → Data → Diagnostics.
 *
 * Existing handler is preserved + re-invoked so the OS still gets a chance
 * to clean up (Activity manager, IPC, etc.) — we never swallow crashes.
 */
@Singleton
class CrashReporter @Inject constructor(
    @ApplicationContext private val context: Context,
    private val breadcrumbs: Breadcrumbs,
) {
    @Volatile
    private var installed = false

    fun install() {
        if (installed) return
        installed = true
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            try {
                writeReport(thread, throwable)
            } catch (t: Throwable) {
                Log.e(TAG, "Crash reporter failed: ${t.message}", t)
            } finally {
                // Hand off to the previous handler (typically the OS default)
                // so the process is torn down + the system logs the trace.
                previous?.uncaughtException(thread, throwable)
            }
        }
    }

    private fun writeReport(thread: Thread, throwable: Throwable) {
        val dir = File(context.filesDir, REPORT_DIR).apply { if (!exists()) mkdirs() }
        val ts = SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).format(Date())
        val file = File(dir, "crash-$ts.log")
        val sw = StringWriter().apply {
            PrintWriter(this).use { pw ->
                pw.println("=== Bizarre CRM crash ===")
                pw.println("Time: ${Date()}")
                pw.println("Thread: ${thread.name} (id=${thread.id}, prio=${thread.priority})")
                pw.println("Build: ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE}) ${if (BuildConfig.DEBUG) "debug" else "release"}")
                pw.println("Device: ${Build.MANUFACTURER} ${Build.MODEL} ${Build.PRODUCT}")
                pw.println("Android: ${Build.VERSION.RELEASE} (SDK ${Build.VERSION.SDK_INT})")
                pw.println()
                pw.println("--- Stacktrace ---")
                throwable.printStackTrace(pw)
                pw.println()
                pw.println("--- Suppressed ---")
                throwable.suppressed.forEach {
                    pw.println("Suppressed:"); it.printStackTrace(pw); pw.println()
                }
                pw.println("--- Cause chain ---")
                var cause = throwable.cause
                while (cause != null && cause !== throwable) {
                    pw.println("Caused by:"); cause.printStackTrace(pw); pw.println()
                    cause = cause.cause
                }
                pw.println("--- Breadcrumbs (last ${breadcrumbs.recent().size}) ---")
                breadcrumbs.recent().forEach { pw.println(it) }
            }
        }
        file.writeText(sw.toString())
        // Light-weight rotation: keep newest [MAX_REPORTS] files, drop the rest.
        rotate(dir)
    }

    private fun rotate(dir: File) {
        val files = dir.listFiles()?.sortedByDescending { it.lastModified() } ?: return
        if (files.size <= MAX_REPORTS) return
        files.drop(MAX_REPORTS).forEach { runCatching { it.delete() } }
    }

    private companion object {
        private const val TAG = "CrashReporter"
        private const val REPORT_DIR = "crash-reports"
        private const val MAX_REPORTS = 10
    }
}
