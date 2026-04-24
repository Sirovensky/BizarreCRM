package com.bizarreelectronics.crm.util

import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PersistableBundle

/**
 * §2.13 Security polish — clipboard helpers that know the difference between
 * an id the user wants kept around (e.g. a ticket number) and a short-lived
 * secret (OTP, backup code) that should be wiped shortly after copy.
 *
 * Android 13+ shows the system "X copied to clipboard" toast automatically;
 * we suppress it on sensitive copies by marking the ClipDescription with
 * `android.content.extra.IS_SENSITIVE`.
 *
 * Detection strategy for [clearSensitiveIfPresent]:
 * - All API levels: ClipData is created with [SENSITIVE_LABEL] as the
 *   ClipDescription label — a marker that is invisible to users but readable
 *   by us at background time.
 * - API 24+: additionally stored as a boolean extra under [EXTRA_IS_SENSITIVE_COMPAT]
 *   in the ClipDescription's PersistableBundle extras.
 * - API 33+: additionally stored under the AOSP constant
 *   `ClipDescription.EXTRA_IS_SENSITIVE` (also suppresses the system preview toast).
 *
 * [clearSensitiveIfPresent] checks the description marker only — it never
 * reads or compares clipboard content. Safe to call from any lifecycle hook.
 */
object ClipboardUtil {

    private val handler = Handler(Looper.getMainLooper())

    /** Plain copy — no auto-clear, visible in system clipboard surface. */
    fun copy(context: Context, label: String, text: String) {
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(ClipData.newPlainText(label, text))
    }

    /**
     * Sensitive copy — auto-clears after [clearAfterMillis]. On Android 13+
     * also suppresses the clipboard preview toast via the IS_SENSITIVE
     * extra.
     *
     * The clip is tagged with [SENSITIVE_LABEL] (+ extras on API 24+/33+)
     * so that [clearSensitiveIfPresent] can identify it by marker alone —
     * without ever reading the clipboard content.
     *
     * The handler-based clear is best-effort only: if the process is killed
     * the clipboard will retain the value. [clearSensitiveIfPresent] called
     * from the app-background lifecycle hook adds a second seal for that case.
     */
    fun copySensitive(
        context: Context,
        @Suppress("UNUSED_PARAMETER") label: String,
        text: String,
        clearAfterMillis: Long = DEFAULT_SECRET_TTL_MS,
    ) {
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        // Use SENSITIVE_LABEL as the ClipDescription label on ALL API levels
        // so clearSensitiveIfPresent can detect our clip without reading content.
        val clip = ClipData.newPlainText(SENSITIVE_LABEL, text)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            val extras = PersistableBundle().apply {
                putBoolean(EXTRA_IS_SENSITIVE_COMPAT, true)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    putBoolean(ClipDescription.EXTRA_IS_SENSITIVE, true)
                }
            }
            clip.description.extras = extras
        }
        clipboard.setPrimaryClip(clip)

        handler.postDelayed({
            // Clear only if our sensitive marker is still on the clipboard —
            // avoids touching a clip the user replaced with their own copy.
            clearSensitiveIfPresent(clipboard)
        }, clearAfterMillis)
    }

    /**
     * §1.6 L239 — Clears the clipboard only if the current primary clip was
     * placed there by [copySensitive] AND our sensitive marker is still present
     * in the ClipDescription. Safe to call when no sensitive copy is active
     * (no-op in that case). Called from the app-background lifecycle hook in
     * [com.bizarreelectronics.crm.BizarreCrmApp].
     *
     * Detection is marker-based only — this function NEVER reads, inspects, or
     * compares clipboard content. Only our explicit [SENSITIVE_LABEL] /
     * [EXTRA_IS_SENSITIVE_COMPAT] tag is checked.
     */
    fun clearSensitiveIfPresent(context: Context) {
        val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager ?: return
        clearSensitiveIfPresent(cm)
    }

    /**
     * Returns true if [description] carries our sensitive marker.
     *
     * Exposed as a standalone pure function so unit tests can drive the
     * detection logic without a real ClipboardManager. The Android-framework
     * unpacking (label + extras) is delegated to the framework-free
     * [SensitiveMarker.isSensitive] helper so plain-JVM tests can cover all
     * branches without Robolectric.
     *
     * Detection precedence:
     * 1. Label equals [SENSITIVE_LABEL] — works on all API levels.
     * 2. PersistableBundle extra [EXTRA_IS_SENSITIVE_COMPAT] == true.
     * 3. AOSP [ClipDescription.EXTRA_IS_SENSITIVE] == true (API 33+) — covers
     *    clips set by a future version of this code that drops the label tag.
     */
    fun isSensitive(description: ClipDescription?): Boolean {
        if (description == null) return false
        val extras = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) description.extras else null
        return SensitiveMarker.isSensitive(
            label = description.label?.toString(),
            compatExtra = extras?.getBoolean(EXTRA_IS_SENSITIVE_COMPAT, false) ?: false,
            aospExtra = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU)
                extras?.getBoolean(ClipDescription.EXTRA_IS_SENSITIVE, false) ?: false
            else false,
        )
    }

    fun clearClipboard(context: Context) {
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clearClipboard(clipboard)
    }

    private fun clearSensitiveIfPresent(clipboard: ClipboardManager) {
        val clip = clipboard.primaryClip ?: return
        if (!isSensitive(clip.description)) return
        clearClipboard(clipboard)
    }

    private fun clearClipboard(clipboard: ClipboardManager) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            clipboard.clearPrimaryClip()
        } else {
            // Pre-P there's no clear API — overwrite with an empty clip
            // so at least the secret is evicted.
            clipboard.setPrimaryClip(ClipData.newPlainText("", ""))
        }
    }

    /**
     * Returns the clipboard contents if they look like a 6-digit OTP. Used
     * by the 2FA verify screen to offer a one-tap paste when the user has
     * copied the code from their authenticator / SMS app.
     *
     * Delegates to [OtpParser.extractOtpDigits] with a 6..6 range, preserving
     * the original narrow contract of this function.
     */
    fun detectOtp(context: Context): String? {
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val raw = clipboard.primaryClip?.getItemAt(0)?.text?.toString()
        return OtpParser.extractOtpDigits(raw, 6..6)
    }

    /**
     * §2.4 (L302-L303) — Inspects the primary clipboard item, trims surrounding
     * whitespace/newlines, then extracts the longest consecutive digit run whose
     * length falls within [digits] (default 4..8).
     *
     * Returns `null` when:
     * - clipboard is empty or contains no text,
     * - no digit run within the given range exists in the text.
     *
     * When multiple runs exist, the longest qualifying run is returned (first on
     * ties). Runs longer than the upper bound are excluded — a 10-digit phone
     * number is not an OTP.
     *
     * Security: the extracted value is NEVER logged by this function.
     */
    fun detectOtpFromClipboard(context: Context, digits: IntRange = 4..8): String? {
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val raw = clipboard.primaryClip?.getItemAt(0)?.text?.toString()
        return OtpParser.extractOtpDigits(raw, digits)
    }

    private const val DEFAULT_SECRET_TTL_MS = 30_000L

    /** ClipDescription label applied to every sensitive copy. Used as marker by [isSensitive]. */
    internal const val SENSITIVE_LABEL = "BizarreCRM:sensitive"

    /**
     * PersistableBundle boolean extra key stored on API 24+ to complement the
     * label-based marker. Using a package-namespaced key avoids collisions with
     * AOSP or other app keys.
     */
    internal const val EXTRA_IS_SENSITIVE_COMPAT =
        "com.bizarreelectronics.crm.EXTRA_IS_SENSITIVE"
}

/**
 * §1.6 L239 — Pure sensitive-clip detection logic with no Android framework
 * dependencies. Extracted from [ClipboardUtil] so that unit tests can exercise
 * all detection paths without Robolectric or a real [android.content.ClipDescription].
 *
 * All parameters are plain Kotlin types; the caller ([ClipboardUtil.isSensitive])
 * is responsible for unpacking the Android framework objects.
 */
object SensitiveMarker {

    /**
     * Returns true when any of the three markers indicates a sensitive clip:
     *
     * 1. [label] == [ClipboardUtil.SENSITIVE_LABEL] — set on all API levels by
     *    [ClipboardUtil.copySensitive].
     * 2. [compatExtra] == true — our own `EXTRA_IS_SENSITIVE_COMPAT` boolean
     *    stored on API 24+.
     * 3. [aospExtra] == true — AOSP `ClipDescription.EXTRA_IS_SENSITIVE` on
     *    API 33+.
     *
     * Never inspects the clipboard text — detection is purely by marker.
     */
    fun isSensitive(label: String?, compatExtra: Boolean, aospExtra: Boolean): Boolean =
        label == ClipboardUtil.SENSITIVE_LABEL || compatExtra || aospExtra
}

/**
 * §2.4 (L303) — Pure OTP-digit extraction helper with no Android framework
 * dependencies. Extracted from [ClipboardUtil] so that unit tests can load this
 * object without triggering the `Handler(Looper.getMainLooper())` initialiser
 * that [ClipboardUtil] uses.
 *
 * All functions are stateless pure transformers — no logging, no I/O, no side
 * effects. Safe to call from any thread.
 */
object OtpParser {

    /**
     * Finds the longest consecutive run of digits in [text] whose length falls
     * within [range] (default 4..8, i.e. 4-digit to 8-digit OTPs).
     *
     * Leading/trailing whitespace and newlines in [text] are stripped before
     * scanning so that typical clipboard content like " 123456\n" is handled
     * correctly.
     *
     * Returns `null` when:
     * - [text] is null or blank,
     * - no digit run with length inside [range] exists.
     *
     * Ties (equal-length runs) are broken by first occurrence.
     *
     * @param text  the raw string to search, e.g. clipboard text
     * @param range acceptable digit-run length, inclusive on both ends
     */
    fun extractOtpDigits(text: String?, range: IntRange = 4..8): String? {
        if (text.isNullOrEmpty()) return null
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return null
        return DIGIT_RUN_REGEX
            .findAll(trimmed)
            .map { it.value }
            .filter { it.length in range }
            .maxByOrNull { it.length }
    }

    private val DIGIT_RUN_REGEX = Regex("\\d+")
}