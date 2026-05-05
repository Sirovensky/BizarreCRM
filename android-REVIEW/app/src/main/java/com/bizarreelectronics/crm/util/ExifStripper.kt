package com.bizarreelectronics.crm.util

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.exifinterface.media.ExifInterface
import timber.log.Timber
import java.io.File
import java.io.FileOutputStream

/**
 * ExifStripper — §4.2 L669
 *
 * Removes privacy-sensitive EXIF metadata from JPEG files before upload.
 * Sensitive tags cleared: GPS coordinates, GPS timestamp, GPS altitude,
 * GPS direction, camera Make/Model, software string, DateTime fields.
 *
 * Usage:
 * ```
 * val cleanFile = ExifStripper.strip(bitmap, outputFile)
 * ```
 *
 * All methods are safe to call from a background thread. Do NOT call on
 * the main thread — bitmap compression is CPU-intensive.
 */
object ExifStripper {

    private const val TAG = "ExifStripper"

    /** GPS and identity tags to null-out before upload. */
    private val SENSITIVE_TAGS = listOf(
        ExifInterface.TAG_GPS_LATITUDE,
        ExifInterface.TAG_GPS_LATITUDE_REF,
        ExifInterface.TAG_GPS_LONGITUDE,
        ExifInterface.TAG_GPS_LONGITUDE_REF,
        ExifInterface.TAG_GPS_ALTITUDE,
        ExifInterface.TAG_GPS_ALTITUDE_REF,
        ExifInterface.TAG_GPS_TIMESTAMP,
        ExifInterface.TAG_GPS_DATESTAMP,
        ExifInterface.TAG_GPS_IMG_DIRECTION,
        ExifInterface.TAG_GPS_IMG_DIRECTION_REF,
        ExifInterface.TAG_GPS_SPEED,
        ExifInterface.TAG_GPS_SPEED_REF,
        ExifInterface.TAG_GPS_DEST_LATITUDE,
        ExifInterface.TAG_GPS_DEST_LONGITUDE,
        ExifInterface.TAG_GPS_DEST_BEARING,
        ExifInterface.TAG_GPS_AREA_INFORMATION,
        ExifInterface.TAG_MAKE,
        ExifInterface.TAG_MODEL,
        ExifInterface.TAG_DATETIME,
        ExifInterface.TAG_DATETIME_ORIGINAL,
        ExifInterface.TAG_DATETIME_DIGITIZED,
        ExifInterface.TAG_SOFTWARE,
        ExifInterface.TAG_ARTIST,
        ExifInterface.TAG_COPYRIGHT,
        ExifInterface.TAG_IMAGE_DESCRIPTION,
        ExifInterface.TAG_USER_COMMENT,
        ExifInterface.TAG_CAMERA_OWNER_NAME,
        ExifInterface.TAG_BODY_SERIAL_NUMBER,
        ExifInterface.TAG_LENS_SERIAL_NUMBER,
        ExifInterface.TAG_LENS_MAKE,
        ExifInterface.TAG_LENS_MODEL,
    )

    /**
     * Compresses [bitmap] to JPEG at 90 % quality into [outputFile] and then
     * strips all sensitive EXIF tags from the written file.
     *
     * @param bitmap     The source bitmap (may already be decoded from a URI).
     * @param outputFile Destination file. Parent directory must already exist.
     * @return           The [outputFile] with sensitive metadata removed, or null on error.
     */
    fun strip(bitmap: Bitmap, outputFile: File): File? {
        return runCatching {
            // 1. Write bitmap to file
            FileOutputStream(outputFile).use { out ->
                bitmap.compress(Bitmap.CompressFormat.JPEG, 90, out)
            }
            // 2. Strip EXIF from the written file
            stripFromFile(outputFile)
            outputFile
        }.onFailure { e ->
            Timber.tag(TAG).e(e, "Failed to strip EXIF from bitmap -> %s", outputFile.name)
        }.getOrNull()
    }

    /**
     * Strips all sensitive EXIF tags in-place from an existing JPEG [file].
     * Non-JPEG files are silently skipped (ExifInterface will throw and we
     * catch it).
     *
     * @param file The file to strip. Must be readable and writable.
     */
    fun stripFromFile(file: File) {
        runCatching {
            val exif = ExifInterface(file.absolutePath)
            var changed = false
            for (tag in SENSITIVE_TAGS) {
                if (exif.getAttribute(tag) != null) {
                    exif.setAttribute(tag, null)
                    changed = true
                }
            }
            if (changed) {
                exif.saveAttributes()
                Timber.tag(TAG).d("Stripped EXIF from %s", file.name)
            }
        }.onFailure { e ->
            Timber.tag(TAG).w(e, "Could not strip EXIF from %s (non-JPEG?)", file.name)
        }
    }
}
