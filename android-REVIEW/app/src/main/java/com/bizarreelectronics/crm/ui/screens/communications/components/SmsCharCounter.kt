package com.bizarreelectronics.crm.ui.screens.communications.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.ui.theme.BrandMono

// GSM-7 basic character set (plus GSM-7 extension table additions in compose field context).
// This covers the characters that fit in 7 bits — anything outside is UCS-2.
private val GSM7_CHARS = setOf(
    '@', '£', '$', '¥', 'è', 'é', 'ù', 'ì', 'ò', 'Ç', '\n', 'Ø', 'ø', '\r', 'Å', 'å',
    'Δ', '_', 'Φ', 'Γ', 'Λ', 'Ω', 'Π', 'Ψ', 'Σ', 'Θ', 'Ξ', '\u001B', 'Æ', 'æ', 'ß', 'É',
    ' ', '!', '"', '#', '¤', '%', '&', '\'', '(', ')', '*', '+', ',', '-', '.', '/',
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ':', ';', '<', '=', '>', '?',
    '¡', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O',
    'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', 'Ä', 'Ö', 'Ñ', 'Ü', '§',
    '¿', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o',
    'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', 'ä', 'ö', 'ñ', 'ü', 'à',
)

/** Returns true if every character fits in the GSM-7 basic + extension table. */
private fun isGsm7(text: String): Boolean = text.all { it in GSM7_CHARS }

/**
 * SMS segment breakdown for a given [text]:
 *
 * GSM-7:
 *   single-part cap = 160 chars, multi-part cap = 153 chars per segment
 * UCS-2:
 *   single-part cap = 70 chars, multi-part cap = 67 chars per segment
 */
data class SmsSegmentInfo(
    val charCount: Int,
    val encoding: String,         // "GSM-7" or "UCS-2"
    val charsPerSegment: Int,
    val segments: Int,
    val estimatedCostUsd: Double, // stub: $0.01 / segment
)

fun computeSegmentInfo(text: String): SmsSegmentInfo {
    val len = text.length
    val gsm7 = isGsm7(text)
    val singleCap = if (gsm7) 160 else 70
    val multiCap = if (gsm7) 153 else 67
    val segments = if (len == 0) 0
    else if (len <= singleCap) 1
    else ((len + multiCap - 1) / multiCap)
    val charsPerSegment = if (segments <= 1) singleCap else multiCap
    return SmsSegmentInfo(
        charCount = len,
        encoding = if (gsm7) "GSM-7" else "UCS-2",
        charsPerSegment = charsPerSegment,
        segments = segments,
        estimatedCostUsd = segments * 0.01,
    )
}

/**
 * Live SMS character counter + segment count + cost estimate.
 * Renders below the compose field in [BrandMono] labelSmall.
 *
 * Shows red when over single-segment limit (160 / 70 chars).
 */
@Composable
fun SmsCharCounter(
    text: String,
    modifier: Modifier = Modifier,
) {
    val info = remember(text) { computeSegmentInfo(text) }
    val scheme = MaterialTheme.colorScheme
    val singleCap = if (info.encoding == "GSM-7") 160 else 70
    val isOver = info.charCount > singleCap
    val textColor = if (isOver) scheme.error else scheme.onSurfaceVariant

    val charsRemaining = if (info.segments <= 1) singleCap - info.charCount
    else info.charsPerSegment - (info.charCount % info.charsPerSegment).let { if (it == 0) info.charsPerSegment else it }

    val costLabel = if (info.segments > 0) " · ~\$%.2f".format(info.estimatedCostUsd) else ""
    val label = "${info.charCount} / ${info.charsPerSegment} · ${info.segments} seg${costLabel} · ${info.encoding}"

    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 2.dp),
        horizontalArrangement = Arrangement.End,
    ) {
        Text(
            text = label,
            style = BrandMono.copy(fontSize = MaterialTheme.typography.labelSmall.fontSize),
            color = textColor,
        )
    }
}
