package com.bizarreelectronics.crm.util

import android.graphics.Bitmap
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter

/**
 * §2.4 L298 — Pure on-device QR code generator backed by ZXing `core`.
 *
 * No network call, no Android view dependency — just a [Bitmap] you can hand to
 * `Image(bitmap.asImageBitmap())` in Compose. Used exclusively for rendering
 * the 2FA enrollment `otpauth://` URI as a scannable QR image.
 *
 * Design decisions:
 * - Uses [QRCodeWriter.encode] which produces a [com.google.zxing.common.BitMatrix].
 * - Allocates an ARGB_8888 [Bitmap] of [sizePx] × [sizePx] and sets each pixel
 *   to either opaque black (`0xFF000000`) or opaque white (`0xFFFFFFFF`).
 * - Error correction level defaults to M (≈15 % recoverable damage) via
 *   [EncodeHintType.ERROR_CORRECTION]. Can withstand small logo overlays without
 *   decode failures.
 * - Caller is responsible for catching exceptions (e.g. invalid input content).
 *
 * For pure-JVM unit testing (no [android.graphics.Bitmap] available in the JVM
 * test scope), use [QrCodeGeneratorPure.generateQrPixels] which returns an
 * [IntArray] of ARGB pixel values instead.
 */
object QrCodeGenerator {

    private const val BLACK = 0xFF000000.toInt()
    private const val WHITE = 0xFFFFFFFF.toInt()

    /**
     * Encodes [contents] as a QR code and returns an ARGB_8888 [Bitmap] of
     * [sizePx] × [sizePx] pixels.
     *
     * @param contents the string to encode (e.g. an `otpauth://totp/…` URI)
     * @param sizePx   output bitmap dimension in pixels; defaults to 512
     * @return         a non-null, non-empty ARGB_8888 bitmap
     * @throws com.google.zxing.WriterException if ZXing cannot encode the content
     */
    fun generateQrBitmap(contents: String, sizePx: Int = 512): Bitmap {
        require(contents.isNotBlank()) { "QR content must not be blank" }
        require(sizePx > 0) { "sizePx must be positive" }

        val hints = mapOf(
            EncodeHintType.ERROR_CORRECTION to com.google.zxing.qrcode.decoder.ErrorCorrectionLevel.M,
            EncodeHintType.MARGIN to 1,
        )

        val writer = QRCodeWriter()
        val bitMatrix = writer.encode(contents, BarcodeFormat.QR_CODE, sizePx, sizePx, hints)

        val bitmap = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        for (x in 0 until sizePx) {
            for (y in 0 until sizePx) {
                bitmap.setPixel(x, y, if (bitMatrix[x, y]) BLACK else WHITE)
            }
        }
        return bitmap
    }
}

/**
 * §2.4 L298 — Pure-JVM extraction of the ZXing encode + pixel-map logic.
 *
 * Identical algorithm to [QrCodeGenerator.generateQrBitmap] but returns an
 * [IntArray] of ARGB colour values (row-major, top-left origin) instead of
 * an [android.graphics.Bitmap]. This avoids the `android.graphics` dependency
 * that makes [Bitmap] unavailable in plain JVM unit tests.
 *
 * Only intended for use in unit tests. Production code should call
 * [QrCodeGenerator.generateQrBitmap].
 */
object QrCodeGeneratorPure {

    private const val BLACK = 0xFF000000.toInt()
    private const val WHITE = 0xFFFFFFFF.toInt()

    /**
     * Encodes [contents] and returns an [IntArray] of [sizePx]*[sizePx] ARGB pixels.
     *
     * @param contents the string to encode
     * @param sizePx   output dimension; must be positive
     * @throws IllegalArgumentException if [contents] is blank or [sizePx] <= 0
     */
    fun generateQrPixels(contents: String, sizePx: Int = 256): IntArray {
        require(contents.isNotBlank()) { "QR content must not be blank" }
        require(sizePx > 0) { "sizePx must be positive" }

        val hints = mapOf(
            EncodeHintType.ERROR_CORRECTION to com.google.zxing.qrcode.decoder.ErrorCorrectionLevel.M,
            EncodeHintType.MARGIN to 1,
        )

        val writer = QRCodeWriter()
        val bitMatrix = writer.encode(contents, BarcodeFormat.QR_CODE, sizePx, sizePx, hints)

        val pixels = IntArray(sizePx * sizePx)
        for (y in 0 until sizePx) {
            for (x in 0 until sizePx) {
                pixels[y * sizePx + x] = if (bitMatrix[x, y]) BLACK else WHITE
            }
        }
        return pixels
    }
}
