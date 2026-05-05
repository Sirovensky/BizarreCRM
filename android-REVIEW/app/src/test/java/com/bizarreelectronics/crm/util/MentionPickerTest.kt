package com.bizarreelectronics.crm.util

import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.TextFieldValue
import com.bizarreelectronics.crm.data.remote.dto.EmployeeListItem
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Unit tests for [MentionUtil] — pure-Kotlin, no Android/Compose UI runtime.
 *
 * Covers @ trigger detection and mention token insertion.
 */
class MentionPickerTest {

    private fun employee(
        id: Long = 1L,
        first: String = "Alice",
        last: String = "Smith",
        username: String = "alice",
    ) = EmployeeListItem(
        id = id,
        username = username,
        email = null,
        firstName = first,
        lastName = last,
        role = null,
        avatarUrl = null,
        isActive = 1,
        hasPin = 0,
        permissions = null,
        createdAt = null,
        updatedAt = null,
    )

    // ─── mentionQueryAtCursor ────────────────────────────────────────────────

    @Test
    fun `returns query fragment after @ trigger`() {
        val value = TextFieldValue("Hey @jo", selection = TextRange(7))
        assertEquals("jo", MentionUtil.mentionQueryAtCursor(value))
    }

    @Test
    fun `returns empty string when @ is the last char`() {
        val value = TextFieldValue("Hey @", selection = TextRange(5))
        assertEquals("", MentionUtil.mentionQueryAtCursor(value))
    }

    @Test
    fun `returns null when no @ in text`() {
        val value = TextFieldValue("Hello world", selection = TextRange(11))
        assertNull(MentionUtil.mentionQueryAtCursor(value))
    }

    @Test
    fun `returns null when space follows @`() {
        val value = TextFieldValue("price @ 5 dollars", selection = TextRange(17))
        assertNull(MentionUtil.mentionQueryAtCursor(value))
    }

    @Test
    fun `returns null when cursor is before @`() {
        val value = TextFieldValue("Hey @alice", selection = TextRange(2))
        assertNull(MentionUtil.mentionQueryAtCursor(value))
    }

    // ─── insertMention ───────────────────────────────────────────────────────

    @Test
    fun `inserts mention token replacing @ trigger`() {
        val value = TextFieldValue("Hello @jo", selection = TextRange(9))
        val emp = employee(id = 42L, first = "John", last = "Doe")
        val result = MentionUtil.insertMention(value, emp)
        // Token format: [@mention:42]
        assertEquals("Hello [@mention:42]", result.text)
    }

    @Test
    fun `cursor is placed after inserted token`() {
        val value = TextFieldValue("Note @al more", selection = TextRange(8))
        val emp = employee(id = 7L, first = "Alice", last = "Brown")
        val result = MentionUtil.insertMention(value, emp)
        val expectedToken = "[@mention:7]"
        val expectedCursor = "Note ".length + expectedToken.length
        assertEquals(expectedCursor, result.selection.start)
    }

    @Test
    fun `text after trigger is preserved`() {
        // Cursor right after the trigger, not at end
        val value = TextFieldValue("Hello @jo world", selection = TextRange(9))
        val emp = employee(id = 1L, first = "Jo", last = "Doe")
        val result = MentionUtil.insertMention(value, emp)
        assertTrue(result.text.endsWith(" world"))
    }

    @Test
    fun `inserting when no @ is a no-op`() {
        val value = TextFieldValue("Hello world", selection = TextRange(11))
        val emp = employee()
        val result = MentionUtil.insertMention(value, emp)
        assertEquals(value.text, result.text)
    }

    // ─── tokensToDisplay ─────────────────────────────────────────────────────

    @Test
    fun `converts mention token to display name`() {
        val employees = listOf(employee(id = 5L, first = "Bob", last = "Jones"))
        val raw = "cc [@mention:5] please"
        assertEquals("cc @Bob Jones please", MentionUtil.tokensToDisplay(raw, employees))
    }

    @Test
    fun `unknown id falls back to question mark`() {
        val employees = emptyList<EmployeeListItem>()
        val raw = "cc [@mention:99] please"
        assertEquals("cc @? please", MentionUtil.tokensToDisplay(raw, employees))
    }

    @Test
    fun `multiple tokens are replaced`() {
        val employees = listOf(
            employee(id = 1L, first = "Alice", last = "A"),
            employee(id = 2L, first = "Bob", last = "B"),
        )
        val raw = "[@mention:1] and [@mention:2] both please"
        assertEquals("@Alice A and @Bob B both please", MentionUtil.tokensToDisplay(raw, employees))
    }
}

private fun assertTrue(msg: String, condition: Boolean) {
    org.junit.Assert.assertTrue(msg, condition)
}
private fun assertTrue(condition: Boolean) {
    org.junit.Assert.assertTrue(condition)
}
