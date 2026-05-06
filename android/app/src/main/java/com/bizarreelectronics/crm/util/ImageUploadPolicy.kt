package com.bizarreelectronics.crm.util

import android.content.Context
import android.net.Uri
import java.io.File

object ImageUploadPolicy {
    const val GENERAL_IMAGE_MAX_BYTES: Long = 10L * 1024L * 1024L
    const val SMALL_IMAGE_MAX_BYTES: Long = 5L * 1024L * 1024L
    const val FORMAT_ERROR: String =
        "Use JPEG, PNG, WebP, or GIF. HEIC/HEIF, TIFF, and DNG/RAW are not supported yet; convert to JPEG before uploading."

    private val supportedMimes = setOf("image/jpeg", "image/png", "image/webp", "image/gif")

    fun isSupportedMime(mime: String?): Boolean =
        mime?.trim()?.lowercase()?.let { supportedMimes.contains(it) } == true

    fun extensionForMime(mime: String?): String = when (mime?.trim()?.lowercase()) {
        "image/png" -> "png"
        "image/webp" -> "webp"
        "image/gif" -> "gif"
        else -> "jpg"
    }

    fun formatSize(bytes: Long): String =
        if (bytes % (1024L * 1024L) == 0L) "${bytes / (1024L * 1024L)} MB" else "${bytes / 1024L} KB"

    fun sizeOf(context: Context, uri: Uri): Long =
        context.contentResolver.openFileDescriptor(uri, "r")?.use { it.statSize } ?: -1L

    fun validate(context: Context, uri: Uri, maxBytes: Long): String? {
        val mime = context.contentResolver.getType(uri)
        if (!isSupportedMime(mime)) return FORMAT_ERROR
        val size = sizeOf(context, uri)
        if (size == 0L) return "Selected image is empty."
        if (size > maxBytes) return "Image exceeds the ${formatSize(maxBytes)} size limit."
        return null
    }

    fun validate(file: File, mime: String, maxBytes: Long): String? {
        if (!isSupportedMime(mime)) return FORMAT_ERROR
        if (file.length() == 0L) return "Selected image is empty."
        if (file.length() > maxBytes) return "Image exceeds the ${formatSize(maxBytes)} size limit."
        return null
    }
}
