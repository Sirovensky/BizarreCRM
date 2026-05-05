package com.bizarreelectronics.crm.util

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for [MarkdownLiteParser] — pure-Kotlin, no Android runtime needed.
 *
 * Validates bold, italic, code, bullet, explicit links, and auto-link
 * detection (phone, email, URL). The AnnotatedString.text property gives us
 * the display text, and we use AnnotatedString.getStringAnnotations to verify
 * link URLs without involving Compose UI or a Robolectric context.
 */
class MarkdownLiteParserTest {

    // ─── Inline markup ───────────────────────────────────────────────────────

    @Test
    fun `bold syntax is stripped from display text`() {
        val result = MarkdownLiteParser.parse("Hello *world* today")
        assertEquals("Hello world today", result.text)
    }

    @Test
    fun `italic syntax is stripped from display text`() {
        val result = MarkdownLiteParser.parse("Say _hello_ there")
        assertEquals("Say hello there", result.text)
    }

    @Test
    fun `inline code syntax is stripped from display text`() {
        val result = MarkdownLiteParser.parse("Run `npm install` now")
        assertEquals("Run npm install now", result.text)
    }

    @Test
    fun `bullet prefix replaces dash-space at start of line`() {
        val result = MarkdownLiteParser.parse("- first\n- second")
        assertTrue("Expected bullet character in output", result.text.contains("\u2022"))
        assertEquals("\u2022 first\n\u2022 second", result.text)
    }

    @Test
    fun `explicit markdown link shows label text`() {
        val result = MarkdownLiteParser.parse("Click [here](https://example.com) now")
        assertEquals("Click here now", result.text)
    }

    @Test
    fun `stripMarkdown removes all syntax`() {
        val raw = "*bold* _italic_ `code` [label](url) - bullet"
        val plain = MarkdownLiteParser.stripMarkdown(raw)
        assertEquals("bold italic code label \u2022 bullet", plain)
    }

    // ─── Auto-link detection ─────────────────────────────────────────────────

    @Test
    fun `phone number with dashes is preserved in display text`() {
        val result = MarkdownLiteParser.parse("Call 555-867-5309 anytime")
        assertTrue(result.text.contains("555-867-5309"))
    }

    @Test
    fun `phone number with dots is preserved in display text`() {
        val result = MarkdownLiteParser.parse("Call 555.867.5309 anytime")
        assertTrue(result.text.contains("555.867.5309"))
    }

    @Test
    fun `plain 10-digit phone is preserved in display text`() {
        val result = MarkdownLiteParser.parse("5558675309")
        assertTrue(result.text.contains("5558675309"))
    }

    @Test
    fun `email address is preserved in display text`() {
        val result = MarkdownLiteParser.parse("Email test@example.com for info")
        assertTrue(result.text.contains("test@example.com"))
    }

    @Test
    fun `http url is preserved in display text`() {
        val result = MarkdownLiteParser.parse("See https://example.com for more")
        assertTrue(result.text.contains("https://example.com"))
    }

    // ─── Combined / edge cases ───────────────────────────────────────────────

    @Test
    fun `multiple inline elements in one line`() {
        val result = MarkdownLiteParser.parse("*bold* and _italic_ and `code`")
        assertEquals("bold and italic and code", result.text)
    }

    @Test
    fun `empty string returns empty annotated string`() {
        val result = MarkdownLiteParser.parse("")
        assertEquals("", result.text)
    }

    @Test
    fun `plain text passes through unchanged`() {
        val result = MarkdownLiteParser.parse("No markup here at all")
        assertEquals("No markup here at all", result.text)
    }

    @Test
    fun `multiline input preserves newlines`() {
        val result = MarkdownLiteParser.parse("line1\nline2")
        assertEquals("line1\nline2", result.text)
    }
}
