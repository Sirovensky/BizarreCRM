package com.bizarreelectronics.crm.ui.screens.settings

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * L1976/L1978 — Unit tests for [SettingsMetadata].
 *
 * No Android context is required — all logic is pure Kotlin.
 */
class SettingsMetadataTest {

    // -------------------------------------------------------------------------
    // Entry lookup by ID
    // -------------------------------------------------------------------------

    @Test
    fun `findById returns entry for known id`() {
        val entry = SettingsMetadata.findById("profile")
        assertNotNull(entry)
        assertEquals("profile", entry!!.id)
        assertEquals("settings/profile", entry.route)
    }

    @Test
    fun `findById returns null for unknown id`() {
        val entry = SettingsMetadata.findById("does-not-exist")
        assertNull(entry)
    }

    @Test
    fun `findById returns security-summary entry`() {
        val entry = SettingsMetadata.findById("security-summary")
        assertNotNull(entry)
        assertEquals("settings/security/summary", entry!!.route)
    }

    // -------------------------------------------------------------------------
    // Keyword search
    // -------------------------------------------------------------------------

    @Test
    fun `search with blank query returns empty list`() {
        val results = SettingsMetadata.search("")
        assertTrue("Expected empty list for blank query", results.isEmpty())
    }

    @Test
    fun `search with whitespace-only query returns empty list`() {
        val results = SettingsMetadata.search("   ")
        assertTrue("Expected empty list for whitespace query", results.isEmpty())
    }

    @Test
    fun `search matches by title case-insensitively`() {
        val results = SettingsMetadata.search("PROFILE")
        assertTrue("Expected at least one result matching 'profile'", results.isNotEmpty())
        assertTrue(results.any { it.id == "profile" })
    }

    @Test
    fun `search matches by keyword`() {
        val results = SettingsMetadata.search("biometric")
        assertTrue("Expected security entry for biometric keyword", results.isNotEmpty())
        assertTrue(results.any { it.id == "security" })
    }

    @Test
    fun `search matches by description`() {
        val results = SettingsMetadata.search("quiet hours")
        assertTrue("Expected notifications entry matching 'quiet hours' description", results.isNotEmpty())
        assertTrue(results.any { it.id == "notifications" })
    }

    @Test
    fun `search returns no results for unmatched query`() {
        val results = SettingsMetadata.search("xyzzy-no-match-at-all-9999")
        assertTrue("Expected no results for unrecognised query", results.isEmpty())
    }

    @Test
    fun `search for timezone matches language entry`() {
        val results = SettingsMetadata.search("timezone")
        assertTrue("Expected language entry for 'timezone'", results.any { it.id == "language" })
    }

    @Test
    fun `search for accent matches appearance entry`() {
        val results = SettingsMetadata.search("accent")
        assertTrue("Expected appearance entry for 'accent'", results.any { it.id == "appearance" })
    }

    // -------------------------------------------------------------------------
    // Invariants
    // -------------------------------------------------------------------------

    @Test
    fun `all entries have non-blank id, title, description, and route`() {
        SettingsMetadata.entries.forEach { entry ->
            assertTrue("Entry id must not be blank: $entry", entry.id.isNotBlank())
            assertTrue("Entry title must not be blank: $entry", entry.title.isNotBlank())
            assertTrue("Entry description must not be blank: $entry", entry.description.isNotBlank())
            assertTrue("Entry route must not be blank: $entry", entry.route.isNotBlank())
        }
    }

    @Test
    fun `all entry ids are unique`() {
        val ids = SettingsMetadata.entries.map { it.id }
        assertEquals("Duplicate entry ids detected", ids.distinct().size, ids.size)
    }

    @Test
    fun `all routes start with settings`() {
        SettingsMetadata.entries.forEach { entry ->
            assertTrue(
                "Route for '${entry.id}' should start with 'settings/': ${entry.route}",
                entry.route.startsWith("settings/"),
            )
        }
    }
}
