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
     * The handler-based clear is best-effort only: if the process is killed
     * the clipboard will retain the value. A follow-up WorkManager worker
     * can harden this once we see real OTP/backup-code copy traffic.
     */
    fun copySensitive(
        context: Context,
        label: String,
        text: String,
        clearAfterMillis: Long = DEFAULT_SECRET_TTL_MS,
    ) {
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val clip = ClipData.newPlainText(label, text)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val extras = PersistableBundle().apply {
                putBoolean(ClipDescription.EXTRA_IS_SENSITIVE, true)
            }
            clip.description.extras = extras
        }
        clipboard.setPrimaryClip(clip)

        handler.postDelayed({
            // Only clear if our sentinel is still on the clipboard —
            // otherwise the user has already pasted somewhere else and
            // replaced it.
            val current = clipboard.primaryClip?.getItemAt(0)?.text?.toString()
            if (current == text) {
                clearClipboard(clipboard)
            }
        }, clearAfterMillis)
    }

    fun clearClipboard(context: Context) {
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
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
     * Delegates to [extractOtpDigits] with a 6..6 range, preserving the
     * original narrow contract of this function.
     */
    fun detectOtp(context: Context): String? {
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val raw = clipboard.primaryClip?.getItemAt(0)?.text?.toString()
        return extractOtpDigits(raw, 6..6)
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
        return extractOtpDigits(raw, digits)
    }

    /**
     * Pure helper that extracts the longest qualifying digit run from [text].
     *
     * Exposed at object scope so unit tests can drive it directly without
     * needing a real Android ClipboardManager. The function is a pure string
     * transformer — no logging, no I/O, no side effects.
     *
     * @param text  raw clipboard text, may be null or blank
     * @param range acceptable digit-run length (inclusive on both ends)
     * @return the longest qualifying digit run, or null if none found
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

    private const val DEFAULT_SECRET_TTL_MS = 30_000L
    private val DIGIT_RUN_REGEX = Regex("\\d+")
}
