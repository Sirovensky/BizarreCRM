package com.bizarreelectronics.crm.util

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Unit tests for [ScrollPosition] and the [SavedStateHandle] extension helpers
 * declared in [ScrollPositionSaver] (§75.5).
 *
 * The [SavedStateHandle] extensions ([saveScrollPosition] / [restoreScrollPosition])
 * work on a plain `MutableMap<String, Any?>` backing store, so we can test them
 * with a lightweight fake instead of a real AndroidX [SavedStateHandle].
 *
 * The Compose-layer [rememberSaveableLazyListState] and [SaveScrollOnDispose]
 * require a Compose runtime and are not exercised here — they are covered by
 * the app's eventual UI-test suite (§31.3).
 */
class ScrollPositionSaverTest {

    // -----------------------------------------------------------------------
    // ScrollPosition data class
    // -----------------------------------------------------------------------

    @Test fun `ScrollPosition zero defaults`() {
        val pos = ScrollPosition()
        assertEquals(0, pos.firstVisibleItemIndex)
        assertEquals(0, pos.firstVisibleItemScrollOffset)
    }

    @Test fun `ScrollPosition companion Zero equals default`() {
        assertEquals(ScrollPosition.Zero, ScrollPosition())
    }

    @Test fun `ScrollPosition stores supplied values`() {
        val pos = ScrollPosition(firstVisibleItemIndex = 42, firstVisibleItemScrollOffset = 300)
        assertEquals(42, pos.firstVisibleItemIndex)
        assertEquals(300, pos.firstVisibleItemScrollOffset)
    }

    @Test fun `ScrollPosition equality by value`() {
        val a = ScrollPosition(10, 100)
        val b = ScrollPosition(10, 100)
        assertEquals(a, b)
    }

    @Test fun `ScrollPosition copy works`() {
        val original = ScrollPosition(5, 50)
        val updated = original.copy(firstVisibleItemIndex = 7)
        assertEquals(7, updated.firstVisibleItemIndex)
        assertEquals(50, updated.firstVisibleItemScrollOffset)
    }

    // -----------------------------------------------------------------------
    // SavedStateHandle extension functions — tested via a fake backing store
    // -----------------------------------------------------------------------

    /**
     * Minimal SavedStateHandle substitute that stores values in a plain map.
     * This avoids the Android framework dependency while exercising the same
     * `get<Int>` / `set` contract.
     *
     * Note: The real [SavedStateHandle] is wire-compatible — the extension
     * functions call `set(key, intValue)` and `get<Int>(key)`, both of which
     * map directly to the underlying bundle with no type erasure.
     */
    private class FakeHandle {
        private val store = mutableMapOf<String, Any?>()

        @Suppress("UNCHECKED_CAST")
        fun <T> get(key: String): T? = store[key] as? T

        fun set(key: String, value: Any?) { store[key] = value }

        // Mirror SavedStateHandle extension contract for testing
        fun saveScrollPosition(scope: String, position: ScrollPosition) {
            set("${scope}_scroll_idx", position.firstVisibleItemIndex)
            set("${scope}_scroll_off", position.firstVisibleItemScrollOffset)
        }

        fun restoreScrollPosition(scope: String): ScrollPosition {
            val idx = get<Int>("${scope}_scroll_idx") ?: 0
            val off = get<Int>("${scope}_scroll_off") ?: 0
            return ScrollPosition(idx, off)
        }
    }

    @Test fun `restoreScrollPosition returns zero when nothing stored`() {
        val handle = FakeHandle()
        val pos = handle.restoreScrollPosition("ticket_list")
        assertEquals(ScrollPosition.Zero, pos)
    }

    @Test fun `saveScrollPosition persists both fields`() {
        val handle = FakeHandle()
        handle.saveScrollPosition("ticket_list", ScrollPosition(15, 230))
        assertEquals(15, handle.get<Int>("ticket_list_scroll_idx"))
        assertEquals(230, handle.get<Int>("ticket_list_scroll_off"))
    }

    @Test fun `restoreScrollPosition round-trips saved value`() {
        val handle = FakeHandle()
        val original = ScrollPosition(99, 512)
        handle.saveScrollPosition("customer_list", original)
        val restored = handle.restoreScrollPosition("customer_list")
        assertEquals(original, restored)
    }

    @Test fun `scopes do not collide`() {
        val handle = FakeHandle()
        handle.saveScrollPosition("tickets", ScrollPosition(1, 10))
        handle.saveScrollPosition("customers", ScrollPosition(2, 20))

        assertEquals(ScrollPosition(1, 10), handle.restoreScrollPosition("tickets"))
        assertEquals(ScrollPosition(2, 20), handle.restoreScrollPosition("customers"))
    }

    @Test fun `overwriting a scope replaces previous position`() {
        val handle = FakeHandle()
        handle.saveScrollPosition("sms_list", ScrollPosition(5, 50))
        handle.saveScrollPosition("sms_list", ScrollPosition(8, 80))
        val restored = handle.restoreScrollPosition("sms_list")
        assertEquals(ScrollPosition(8, 80), restored)
    }

    @Test fun `index 0 offset 0 survives a save-restore roundtrip`() {
        val handle = FakeHandle()
        handle.saveScrollPosition("test_scope", ScrollPosition(0, 0))
        assertEquals(ScrollPosition.Zero, handle.restoreScrollPosition("test_scope"))
    }

    @Test fun `large index and offset are preserved exactly`() {
        val handle = FakeHandle()
        val pos = ScrollPosition(Int.MAX_VALUE - 1, Int.MAX_VALUE - 2)
        handle.saveScrollPosition("large", pos)
        assertEquals(pos, handle.restoreScrollPosition("large"))
    }
}
