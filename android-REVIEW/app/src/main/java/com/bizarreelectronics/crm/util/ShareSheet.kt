package com.bizarreelectronics.crm.util

import android.content.Context
import android.content.Intent

/**
 * Thin wrapper around the Android share-sheet (ACTION_SEND).
 *
 * All outgoing shares go through this single entry-point so we can
 * keep the intent construction consistent and add analytics hooks
 * later without scattering Intent boilerplate across screens.
 */
object ShareSheet {

    /**
     * Open the system share-sheet with [text] as plain-text content.
     *
     * @param context  Activity or application context.
     * @param text     The text to share (e.g. a URL or a short message + URL).
     * @param title    Optional chooser dialog title shown on older Android versions.
     */
    fun shareText(context: Context, text: String, title: String? = null) {
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, text)
            if (title != null) putExtra(Intent.EXTRA_SUBJECT, title)
        }
        context.startActivity(Intent.createChooser(intent, title))
    }
}
