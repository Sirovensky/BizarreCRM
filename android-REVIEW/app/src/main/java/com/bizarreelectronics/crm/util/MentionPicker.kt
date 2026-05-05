package com.bizarreelectronics.crm.util

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.withStyle
import com.bizarreelectronics.crm.data.remote.dto.EmployeeListItem
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.delay

/**
 * Utility helpers for @mention detection in a [TextFieldValue].
 *
 * Backend persistence format: `[@mention:userId]`
 * Display format: `@displayName` with primary-color + bold SpanStyle.
 */
object MentionUtil {

    private val MENTION_TOKEN_RE = Regex("""\[@mention:(\d+)]""")

    /**
     * Returns the incomplete @-trigger query at the cursor position, or null
     * if the cursor is not inside an @-trigger span.
     *
     * Example: "Hey @jo|hn more text" → "jo" (| = cursor)
     */
    fun mentionQueryAtCursor(value: TextFieldValue): String? {
        val text = value.text
        val cursor = value.selection.end
        // Walk backwards from cursor, looking for @ that has no space between it and cursor
        val beforeCursor = text.substring(0, cursor)
        val atIdx = beforeCursor.lastIndexOf('@')
        if (atIdx < 0) return null
        val between = beforeCursor.substring(atIdx + 1)
        // If there's a space between @ and cursor it's not a live trigger
        if (between.contains(' ') || between.contains('\n')) return null
        return between
    }

    /**
     * Insert a completed mention token at the current @-trigger location.
     * Replaces `@query` with `@{displayName}` visually and `[@mention:userId]` in the raw text.
     *
     * @return updated [TextFieldValue] with the mention inserted and cursor placed after it.
     */
    fun insertMention(
        value: TextFieldValue,
        employee: EmployeeListItem,
    ): TextFieldValue {
        val text = value.text
        val cursor = value.selection.end
        val beforeCursor = text.substring(0, cursor)
        val atIdx = beforeCursor.lastIndexOf('@')
        if (atIdx < 0) return value

        val displayName = listOfNotNull(employee.firstName, employee.lastName).joinToString(" ").ifBlank { employee.username ?: "?" }
        val token = "[@mention:${employee.id}]"
        val replacement = "@$displayName"

        val newText = text.substring(0, atIdx) + token + text.substring(cursor)
        val newCursor = atIdx + token.length

        // Rebuild text applying a visual annotation for the mention span
        return TextFieldValue(
            text = newText,
            selection = TextRange(newCursor),
        )
    }

    /**
     * Convert raw mention tokens `[@mention:id]` to display text `@Name`.
     * Used when rendering saved note text in the compose box.
     */
    fun tokensToDisplay(raw: String, employees: List<EmployeeListItem>): String {
        return MENTION_TOKEN_RE.replace(raw) { match ->
            val id = match.groupValues[1].toLongOrNull()
            val emp = employees.find { it.id == id }
            val name = emp?.let { listOfNotNull(it.firstName, it.lastName).joinToString(" ").ifBlank { it.username ?: "?" } } ?: "?"
            "@$name"
        }
    }
}

/**
 * Overlay dropdown that appears below the compose field when an @-trigger is active.
 *
 * @param expanded      true when the dropdown should be visible.
 * @param suggestions   employee list filtered to the current query.
 * @param onSelect      callback when the user picks a suggestion.
 * @param onDismiss     callback when the user taps outside or presses back.
 */
@Composable
fun MentionPickerDropdown(
    expanded: Boolean,
    suggestions: List<EmployeeListItem>,
    onSelect: (EmployeeListItem) -> Unit,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    DropdownMenu(
        expanded = expanded && suggestions.isNotEmpty(),
        onDismissRequest = onDismiss,
        modifier = modifier,
    ) {
        suggestions.forEach { employee ->
            val displayName = listOfNotNull(employee.firstName, employee.lastName)
                .joinToString(" ")
                .ifBlank { employee.username ?: "?" }
            DropdownMenuItem(
                text = {
                    Text(
                        "@$displayName",
                        style = MaterialTheme.typography.bodySmall.copy(
                            color = MaterialTheme.colorScheme.primary,
                            fontWeight = FontWeight.SemiBold,
                        ),
                    )
                },
                onClick = { onSelect(employee) },
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}
