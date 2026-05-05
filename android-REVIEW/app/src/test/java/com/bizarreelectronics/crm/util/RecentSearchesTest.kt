package com.bizarreelectronics.crm.util

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * §31.1 — unit coverage for §18.1 RecentSearches cache helper.
 */
class RecentSearchesTest {

    @Test fun `prepend inserts at index 0`() {
        val result = RecentSearches.prepend(listOf("a", "b"), "c")
        assertEquals(listOf("c", "a", "b"), result)
    }

    @Test fun `prepend trims whitespace`() {
        val result = RecentSearches.prepend(emptyList(), "  iphone  ")
        assertEquals(listOf("iphone"), result)
    }

    @Test fun `blank query is a no-op`() {
        val current = listOf("a", "b")
        assertEquals(current, RecentSearches.prepend(current, ""))
        assertEquals(current, RecentSearches.prepend(current, "   "))
    }

    @Test fun `repeat query shuffles to front, no duplicate`() {
        val result = RecentSearches.prepend(listOf("a", "b", "c"), "b")
        assertEquals(listOf("b", "a", "c"), result)
    }

    @Test fun `dedupe is case-insensitive`() {
        val result = RecentSearches.prepend(listOf("iPhone", "Galaxy"), "IPHONE")
        assertEquals(listOf("IPHONE", "Galaxy"), result)
    }

    @Test fun `list is capped at LIMIT`() {
        val seed = (1..RecentSearches.LIMIT).map { "q$it" }
        val result = RecentSearches.prepend(seed, "new")
        assertEquals(RecentSearches.LIMIT, result.size)
        assertEquals("new", result.first())
        // oldest ("q8") falls off the end
        assertEquals("q7", result.last())
    }

    @Test fun `remove strips one entry case-insensitively`() {
        val result = RecentSearches.remove(listOf("iPhone", "Galaxy", "Pixel"), "galaxy")
        assertEquals(listOf("iPhone", "Pixel"), result)
    }

    @Test fun `remove of missing entry returns input unchanged`() {
        val current = listOf("a", "b")
        assertEquals(current, RecentSearches.remove(current, "c"))
    }

    @Test fun `serialize roundtrip preserves order`() {
        val seed = listOf("iPhone 15", "Galaxy S24", "Pixel 9")
        val raw = RecentSearches.serialize(seed)
        assertEquals(seed, RecentSearches.deserialize(raw))
    }

    @Test fun `deserialize tolerates empty and null`() {
        assertEquals(emptyList<String>(), RecentSearches.deserialize(null))
        assertEquals(emptyList<String>(), RecentSearches.deserialize(""))
    }
}
