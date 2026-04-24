package com.bizarreelectronics.crm.ui.components.auth

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.util.PasswordStrength

/**
 * Reusable password strength meter composable.
 *
 * Renders a 5-segment horizontal bar that fills progressively as the password
 * gains strength, followed by a compact rule checklist with Done / Clear icons.
 *
 * Suitable for: SetPasswordStep, ChangePasswordScreen, ResetPasswordScreen.
 * Callers simply pass the current password string and an optional [modifier].
 *
 * No state is held inside this composable — strength is re-derived on each
 * recomposition from the immutable [password] value.
 *
 * @param password  The password string to evaluate (not mutated).
 * @param modifier  Applied to the outer [Column].
 */
@Composable
fun PasswordStrengthMeter(
    password: String,
    modifier: Modifier = Modifier,
) {
    val result = PasswordStrength.evaluate(password)

    Column(modifier = modifier.fillMaxWidth()) {
        StrengthBar(level = result.level)
        Spacer(Modifier.height(8.dp))
        RuleChecklist(checks = result.ruleChecks)
    }
}

// ─── Segmented bar ──────────────────────────────────────────────────

/** Maps [PasswordStrength.Level] to segment count (out of 5) and display colour. */
private data class StrengthStyle(
    val filledSegments: Int,
    val color: Color,
    val label: String,
)

@Composable
private fun strengthStyleFor(level: PasswordStrength.Level): StrengthStyle {
    val colorScheme = MaterialTheme.colorScheme
    return when (level) {
        PasswordStrength.Level.NONE       -> StrengthStyle(0, colorScheme.outlineVariant, "")
        PasswordStrength.Level.WEAK       -> StrengthStyle(1, colorScheme.error,           "Weak")
        PasswordStrength.Level.FAIR       -> StrengthStyle(3, Color(0xFFF59E0B),            "Fair")
        PasswordStrength.Level.STRONG     -> StrengthStyle(4, Color(0xFF22C55E),            "Strong")
        PasswordStrength.Level.VERY_STRONG -> StrengthStyle(5, Color(0xFF16A34A),           "Very strong")
    }
}

@Composable
private fun StrengthBar(level: PasswordStrength.Level) {
    val style = strengthStyleFor(level)
    val totalSegments = 5
    val filledColor = style.color
    val emptyColor = MaterialTheme.colorScheme.outlineVariant

    Column {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(3.dp),
        ) {
            repeat(totalSegments) { index ->
                val segmentColor = if (index < style.filledSegments) filledColor else emptyColor
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .height(4.dp)
                        .clip(RoundedCornerShape(2.dp))
                        .background(segmentColor),
                )
            }
        }
        if (style.label.isNotEmpty()) {
            Spacer(Modifier.height(2.dp))
            Text(
                text = style.label,
                style = MaterialTheme.typography.labelSmall,
                color = filledColor,
            )
        }
    }
}

// ─── Rule checklist ──────────────────────────────────────────────────

private fun ruleLabel(rule: PasswordStrength.Rule): String = when (rule) {
    PasswordStrength.Rule.MIN_LENGTH -> "At least 8 characters"
    PasswordStrength.Rule.HAS_LOWER  -> "Lowercase letter"
    PasswordStrength.Rule.HAS_UPPER  -> "Uppercase letter"
    PasswordStrength.Rule.HAS_DIGIT  -> "Number"
    PasswordStrength.Rule.HAS_SYMBOL -> "Symbol (!@#\$…)"
    PasswordStrength.Rule.NOT_COMMON -> "Not a common password"
}

@Composable
private fun RuleChecklist(checks: Map<PasswordStrength.Rule, Boolean>) {
    val orderedRules = PasswordStrength.Rule.values()
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        orderedRules.forEach { rule ->
            val passing = checks[rule] == true
            val icon = if (passing) Icons.Default.Check else Icons.Default.Close
            val iconTint = if (passing) Color(0xFF22C55E) else MaterialTheme.colorScheme.onSurfaceVariant
            val textColor = if (passing) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant

            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Icon(
                    imageVector = icon,
                    contentDescription = if (passing) "Passed" else "Not passed",
                    modifier = Modifier.size(14.dp),
                    tint = iconTint,
                )
                Text(
                    text = ruleLabel(rule),
                    style = MaterialTheme.typography.labelSmall,
                    color = textColor,
                )
            }
        }
    }
}
