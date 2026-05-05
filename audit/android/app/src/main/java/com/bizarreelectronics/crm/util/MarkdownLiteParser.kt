package com.bizarreelectronics.crm.util

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle

/**
 * Pure-Kotlin markdown-lite parser → AnnotatedString (no WebView).
 *
 * Supported syntax:
 *  - `*bold*`               → FontWeight.Bold
 *  - `_italic_`             → FontStyle.Italic
 *  - `` `code` ``           → monospace + light background
 *  - `- bullet` (line-start) → "• " prefix
 *  - `[label](url)`         → LinkAnnotation.Url
 *
 * Link detection (phone / email / URL):
 *  - Phone  `\d{3}[-.]?\d{3}[-.]?\d{4}` → tel: scheme
 *  - Email  `\S+@\S+\.\S+`              → mailto: scheme
 *  - URL    `https?://\S+`              → direct URL
 */
object MarkdownLiteParser {

    /** Parsed result — AnnotatedString with spans + inline link annotations. */
    fun parse(raw: String, linkColor: Color = Color(0xFF6200EA)): AnnotatedString {
        // Normalize line endings
        val text = raw.replace("\r\n", "\n").replace("\r", "\n")
        val lines = text.split("\n")

        return buildAnnotatedString {
            lines.forEachIndexed { idx, line ->
                // Bullet prefix
                val processedLine = if (line.trimStart().startsWith("- ")) {
                    "\u2022 " + line.trimStart().removePrefix("- ")
                } else {
                    line
                }
                appendInlineMarkdown(processedLine, linkColor)
                if (idx < lines.size - 1) append("\n")
            }
        }
    }

    private fun AnnotatedString.Builder.appendInlineMarkdown(line: String, linkColor: Color) {
        // Order matters: explicit links first, then inline formatting, then auto-detection
        val segments = tokenize(line)
        for (seg in segments) {
            when (seg) {
                is Token.Plain -> appendWithAutoLinks(seg.text, linkColor)
                is Token.Bold -> withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { append(seg.text) }
                is Token.Italic -> withStyle(SpanStyle(fontStyle = FontStyle.Italic)) { append(seg.text) }
                is Token.Code -> withStyle(SpanStyle(fontFamily = FontFamily.Monospace, background = Color(0x22888888))) { append(seg.text) }
                is Token.Link -> {
                    val styles = TextLinkStyles(SpanStyle(color = linkColor, fontWeight = FontWeight.Medium))
                    withLink(LinkAnnotation.Url(seg.url, styles)) { append(seg.label) }
                }
            }
        }
    }

    // -------------------------------------------------------------------------
    // Tokenizer
    // -------------------------------------------------------------------------

    private sealed class Token {
        data class Plain(val text: String) : Token()
        data class Bold(val text: String) : Token()
        data class Italic(val text: String) : Token()
        data class Code(val text: String) : Token()
        data class Link(val label: String, val url: String) : Token()
    }

    private val INLINE_PATTERN = Regex(
        """\[([^\]]+)]\(([^)]+)\)|`([^`]+)`|\*([^*]+)\*|_([^_]+)_""",
    )

    private fun tokenize(line: String): List<Token> {
        val tokens = mutableListOf<Token>()
        var cursor = 0
        for (match in INLINE_PATTERN.findAll(line)) {
            if (match.range.first > cursor) {
                tokens += Token.Plain(line.substring(cursor, match.range.first))
            }
            tokens += when {
                match.groupValues[1].isNotEmpty() -> Token.Link(match.groupValues[1], match.groupValues[2])
                match.groupValues[3].isNotEmpty() -> Token.Code(match.groupValues[3])
                match.groupValues[4].isNotEmpty() -> Token.Bold(match.groupValues[4])
                match.groupValues[5].isNotEmpty() -> Token.Italic(match.groupValues[5])
                else -> Token.Plain(match.value)
            }
            cursor = match.range.last + 1
        }
        if (cursor < line.length) tokens += Token.Plain(line.substring(cursor))
        return tokens
    }

    // -------------------------------------------------------------------------
    // Auto-link detection (phone / email / URL)
    // -------------------------------------------------------------------------

    private val PHONE_RE = Regex("""(?<!\d)\d{3}[-.· ]?\d{3}[-.· ]?\d{4}(?!\d)""")
    private val EMAIL_RE = Regex("""[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}""")
    private val URL_RE = Regex("""https?://\S+""")
    private val AUTO_RE = Regex(
        """(${URL_RE.pattern})|(${EMAIL_RE.pattern})|(${PHONE_RE.pattern})""",
    )

    private fun AnnotatedString.Builder.appendWithAutoLinks(text: String, linkColor: Color) {
        var cursor = 0
        for (match in AUTO_RE.findAll(text)) {
            if (match.range.first > cursor) append(text.substring(cursor, match.range.first))

            val value = match.value
            val scheme = when {
                URL_RE.matches(value) -> value
                EMAIL_RE.matches(value) -> "mailto:$value"
                else -> "tel:${value.replace(Regex("[^0-9+]"), "")}"
            }
            val styles = TextLinkStyles(SpanStyle(color = linkColor, fontWeight = FontWeight.Medium))
            withLink(LinkAnnotation.Url(scheme, styles)) { append(value) }
            cursor = match.range.last + 1
        }
        if (cursor < text.length) append(text.substring(cursor))
    }

    /**
     * Strip all markdown syntax and return plain text (used for plain-text fields
     * like search index, SMS preview, etc.).
     */
    fun stripMarkdown(raw: String): String =
        raw
            .replace(Regex("""\[([^\]]+)]\([^)]+\)"""), "$1")
            .replace(Regex("""`([^`]+)`"""), "$1")
            .replace(Regex("""\*([^*]+)\*"""), "$1")
            .replace(Regex("""_([^_]+)_"""), "$1")
            .replace(Regex("""^- """, RegexOption.MULTILINE), "• ")
}
