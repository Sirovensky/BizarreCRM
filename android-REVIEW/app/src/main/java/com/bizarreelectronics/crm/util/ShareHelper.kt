package com.bizarreelectronics.crm.util

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import com.bizarreelectronics.crm.R
import timber.log.Timber
import java.io.File

/**
 * §25.2 Share sheet helpers — outbound ACTION_SEND / ACTION_SEND_MULTIPLE
 * and Sharing Shortcuts (direct-share targets) for recent customers.
 *
 * Direct-share requires:
 *  - ShortcutManagerCompat for API-level-agnostic Sharing Shortcuts (Android 10+)
 *    with CATEGORY_SHARE_TARGET category so the system surfaces them in the
 *    chooser. On API < 10 the share works but no direct-share target appears.
 *  - A `res/xml/sharing_shortcuts.xml` shortcuts config (declares <share-target>)
 *    referenced from AndroidManifest.xml via `<meta-data android:name="android.app.shortcuts">`.
 *    The existing shortcuts.xml entry already covers this manifest reference.
 *
 * Outbound share helpers:
 *  - [shareTextPlain]: minimal text share (ticket # deep-link, order IDs, etc.)
 *  - [sharePdf]: single PDF via ACTION_SEND.
 *  - [sharePhotos]: one or more photo URIs via ACTION_SEND / ACTION_SEND_MULTIPLE.
 *  - [shareVCard]: vCard file via ACTION_SEND (already wired in CustomerDetailScreen;
 *    duplicated here so callers can go through a single util instead of the per-screen
 *    ad-hoc intent).
 *
 * Direct-share shortcuts:
 *  - [pushDirectShareCustomers]: called when a customer list loads; pushes the top-4
 *    recents as CATEGORY_SHARE_TARGET shortcuts so the system chooser surfaces them.
 *    Maximum 4 targets to stay within the OS visible-shortcut budget without
 *    crowding other LAUNCHER/PINNED shortcuts.
 *    Each shortcut carries the customer's initials as a synthetic bitmap icon (no
 *    network fetch required; no personal photo stored outside the chip).
 */
object ShareHelper {

    /** Chooser title shown for generic share actions. */
    private const val CHOOSER_SHARE = "Share via…"

    // ─── Outbound text ────────────────────────────────────────────────────────

    /**
     * Share [text] (e.g. a deep-link URL or order ID) as text/plain via the
     * system share sheet. [subject] is used by email clients as a pre-filled subject line.
     */
    fun shareTextPlain(context: Context, text: String, subject: String? = null) {
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, text)
            if (subject != null) putExtra(Intent.EXTRA_SUBJECT, subject)
        }
        runCatching { context.startActivity(Intent.createChooser(intent, CHOOSER_SHARE)) }
            .onFailure { e -> Timber.tag("ShareHelper").w(e, "shareTextPlain failed") }
    }

    // ─── Outbound PDF ─────────────────────────────────────────────────────────

    /**
     * Share a [pdfUri] (FileProvider URI) as application/pdf.
     * [subject] pre-fills the email subject when the chooser targets an email client.
     */
    fun sharePdf(context: Context, pdfUri: Uri, subject: String? = null) {
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "application/pdf"
            putExtra(Intent.EXTRA_STREAM, pdfUri)
            putExtra(Intent.EXTRA_SUBJECT, subject ?: "Document")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        runCatching { context.startActivity(Intent.createChooser(intent, CHOOSER_SHARE)) }
            .onFailure { e -> Timber.tag("ShareHelper").w(e, "sharePdf failed") }
    }

    // ─── Outbound photos ─────────────────────────────────────────────────────

    /**
     * Share one or more photo [uris] via the system share sheet.
     * Uses ACTION_SEND for a single URI or ACTION_SEND_MULTIPLE for several.
     * All URIs must be FileProvider-scoped or publicly readable content:// URIs.
     */
    fun sharePhotos(context: Context, uris: List<Uri>) {
        if (uris.isEmpty()) return
        val intent = if (uris.size == 1) {
            Intent(Intent.ACTION_SEND).apply {
                type = "image/*"
                putExtra(Intent.EXTRA_STREAM, uris[0])
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
        } else {
            Intent(Intent.ACTION_SEND_MULTIPLE).apply {
                type = "image/*"
                putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList(uris))
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
        }
        runCatching { context.startActivity(Intent.createChooser(intent, CHOOSER_SHARE)) }
            .onFailure { e -> Timber.tag("ShareHelper").w(e, "sharePhotos(${uris.size}) failed") }
    }

    // ─── Outbound vCard ───────────────────────────────────────────────────────

    /**
     * Share a vCard [vcfUri] (FileProvider URI) as text/x-vcard.
     * Already wired ad-hoc in CustomerDetailScreen; exposed here for uniform usage.
     */
    fun shareVCard(context: Context, vcfUri: Uri) {
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "text/x-vcard"
            putExtra(Intent.EXTRA_STREAM, vcfUri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        runCatching { context.startActivity(Intent.createChooser(intent, CHOOSER_SHARE)) }
            .onFailure { e -> Timber.tag("ShareHelper").w(e, "shareVCard failed") }
    }

    // ─── Direct-share shortcuts ───────────────────────────────────────────────

    /**
     * Shortcut category declared in res/xml/sharing_shortcuts.xml.
     * Must match <category android:name="…"> under <share-target> exactly so
     * ShortcutManagerCompat can surface these in the chooser's direct-share row.
     */
    private const val CATEGORY_SHARE_TARGET =
        "com.bizarreelectronics.crm.SHARE_TARGET"

    /**
     * §25.2 Direct-share: push up to [MAX_TARGETS] recent customers as
     * CATEGORY_SHARE_TARGET shortcuts into ShortcutManagerCompat.
     *
     * Each shortcut carries:
     *   - A 48×48 bitmap icon built from the customer's initials on a colored
     *     background (using M3 `primaryContainer` hue — resolved as a constant
     *     here to avoid a Compose context dependency).
     *   - [intent] routed to bizarrecrm://customers/<id> so the chooser callback
     *     brings the user directly to the customer detail screen, carrying the
     *     shared content as EXTRA_TEXT / EXTRA_STREAM.
     *
     * @param context   Application context.
     * @param customers List of (id, displayName) pairs, already sorted most-recent-first.
     *                  Only the first [MAX_TARGETS] entries are pushed.
     */
    fun pushDirectShareCustomers(
        context: Context,
        customers: List<Pair<Long, String>>,
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return // Sharing Shortcuts require API 29
        val shortcuts = customers.take(MAX_TARGETS).mapIndexed { index, (id, name) ->
            val icon = makeInitialsIcon(name, ICON_SIZE_PX)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                data = Uri.parse("bizarrecrm://customers/$id")
                `package` = context.packageName
            }
            ShortcutInfoCompat.Builder(context, "direct_share_customer_$id")
                .setShortLabel(name.take(25)) // system trims to ~20 chars in the chooser row
                .setLongLabel(name)
                .setIcon(IconCompat.createWithBitmap(icon))
                .setIntent(intent)
                .setCategories(setOf(CATEGORY_SHARE_TARGET))
                .setRank(index)
                .build()
        }
        runCatching {
            ShortcutManagerCompat.addDynamicShortcuts(context, shortcuts)
        }.onFailure { e ->
            Timber.tag("ShareHelper").w(e, "pushDirectShareCustomers failed")
        }
    }

    private const val MAX_TARGETS = 4
    private const val ICON_SIZE_PX = 96 // 48dp @ 2x — adequate for all density buckets

    /** Build a square bitmap with [initials] centred on a filled background. */
    private fun makeInitialsIcon(name: String, sizePx: Int): Bitmap {
        val initials = name.split(' ')
            .mapNotNull { it.firstOrNull()?.uppercaseChar() }
            .take(2)
            .joinToString("")
            .ifEmpty { "?" }
        val bmp = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        val canvas = android.graphics.Canvas(bmp)
        val bgPaint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
            // Cream brand accent (M3 primaryContainer approximation)
            color = 0xFFCDB687.toInt()
        }
        canvas.drawCircle(sizePx / 2f, sizePx / 2f, sizePx / 2f, bgPaint)
        val textPaint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
            color = 0xFF3E2E0D.toInt() // onPrimaryContainer dark brown
            textSize = sizePx * 0.38f
            textAlign = android.graphics.Paint.Align.CENTER
            isFakeBoldText = true
        }
        val yPos = sizePx / 2f - (textPaint.descent() + textPaint.ascent()) / 2f
        canvas.drawText(initials, sizePx / 2f, yPos, textPaint)
        return bmp
    }
}
