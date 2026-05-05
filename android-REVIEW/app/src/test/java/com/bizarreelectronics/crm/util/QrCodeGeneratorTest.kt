package com.bizarreelectronics.crm.util

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/**
 * §2.4 L298 — Unit tests for [QrCodeGenerator].
 *
 * These tests run on the plain JVM (no Android framework, no Robolectric).
 * [android.graphics.Bitmap] is NOT available in unit-test scope, so the tests
 * verify the pure-JVM logic via the [QrCodeGeneratorPure] helper that is exposed
 * for testing purposes: it returns a [IntArray] of pixel colours rather than a [Bitmap].
 *
 * Coverage:
 *   1. Output dimensions match requested sizePx.
 *   2. Result is non-null and non-empty.
 *   3. Output contains both dark (0xFF000000) and light (0xFFFFFFFF) pixels.
 *   4. Blank content throws [IllegalArgumentException].
 *   5. Zero/negative size throws [IllegalArgumentException].
 */
class QrCodeGeneratorTest {

    @Test
    fun `generateQrPixels returns correct dimensions`() {
        val sizePx = 128
        val result = QrCodeGeneratorPure.generateQrPixels(
            contents = "otpauth://totp/BizarreCRM:testuser?secret=ABCDEFGH&issuer=BizarreCRM",
            sizePx = sizePx,
        )
        assertEquals("pixel array length must equal sizePx * sizePx", sizePx * sizePx, result.size)
    }

    @Test
    fun `generateQrPixels result is non-empty`() {
        val result = QrCodeGeneratorPure.generateQrPixels(
            contents = "otpauth://totp/BizarreCRM:admin?secret=JBSWY3DPEHPK3PXP&issuer=BizarreCRM",
            sizePx = 64,
        )
        assertTrue("pixel array must not be empty", result.isNotEmpty())
    }

    @Test
    fun `generateQrPixels output contains both dark and light pixels`() {
        val result = QrCodeGeneratorPure.generateQrPixels(
            contents = "otpauth://totp/BizarreCRM:admin?secret=JBSWY3DPEHPK3PXP&issuer=BizarreCRM",
            sizePx = 256,
        )
        val darkPixel = 0xFF000000.toInt()
        val lightPixel = 0xFFFFFFFF.toInt()
        val hasDark = result.any { it == darkPixel }
        val hasLight = result.any { it == lightPixel }
        assertTrue("QR bitmap must contain dark (black) pixels", hasDark)
        assertTrue("QR bitmap must contain light (white) pixels", hasLight)
    }

    @Test
    fun `generateQrPixels throws on blank content`() {
        try {
            QrCodeGeneratorPure.generateQrPixels(contents = "", sizePx = 64)
            fail("Expected IllegalArgumentException for blank content")
        } catch (e: IllegalArgumentException) {
            // expected
        }
    }

    @Test
    fun `generateQrPixels throws on zero size`() {
        try {
            QrCodeGeneratorPure.generateQrPixels(contents = "hello", sizePx = 0)
            fail("Expected IllegalArgumentException for zero sizePx")
        } catch (e: IllegalArgumentException) {
            // expected
        }
    }

    @Test
    fun `generateQrPixels throws on negative size`() {
        try {
            QrCodeGeneratorPure.generateQrPixels(contents = "hello", sizePx = -1)
            fail("Expected IllegalArgumentException for negative sizePx")
        } catch (e: IllegalArgumentException) {
            // expected
        }
    }
}
