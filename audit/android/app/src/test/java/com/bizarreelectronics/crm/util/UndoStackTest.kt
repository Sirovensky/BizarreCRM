package com.bizarreelectronics.crm.util

import kotlinx.coroutines.async
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.yield
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * JUnit4 unit tests for [UndoStack] (§1 lines 231-236).
 *
 * All coroutine calls use [runBlocking] — no Android context or coroutines-test
 * library required. [UndoStack] is pure-JVM so these run as Robolectric-free
 * host tests.
 *
 * ### SharedFlow event collection pattern
 *
 * [UndoStack.events] is a `MutableSharedFlow(replay=0, extraBufferCapacity=16)`.
 * The extraBufferCapacity means `tryEmit()` never drops events when a subscriber
 * is registered but busy. However, events emitted before a subscriber registers
 * are still dropped (no replay).
 *
 * In `runBlocking`, child coroutines launched with [async] don't start executing
 * until the current coroutine suspends. To guarantee the async collector registers
 * as a subscriber BEFORE actions are triggered:
 *   1. Launch `async { events.take(N).toList() }`.
 *   2. Call `yield()` to suspend the outer coroutine and let the collector start.
 *   3. Trigger the action (events land in the subscriber's buffer).
 *   4. `await()` to collect results.
 *
 * Coverage:
 *   1.  push + undo restores state
 *   2.  redo after undo re-applies action
 *   3.  push clears redo stack
 *   4.  stack depth capped at maxDepth; oldest entry dropped
 *   5.  canUndo / canRedo StateFlows emit correctly after push/undo/redo/clear
 *   6.  undo() fires reverse and emits UndoEvent.Undone with auditDescription
 *   7.  compensatingSync is invoked on undo when present
 *   8.  compensatingSync returning false → Failed event, stack unchanged
 *   9.  clear() empties both stacks and resets canUndo/canRedo to false
 *  10.  undo() on empty stack returns false
 *  11.  redo() on empty stack returns false
 *  12.  events SharedFlow has replay=0 (late subscriber misses prior events)
 *  13.  auditDescription is present on every event type
 *  14.  multiple undo/redo round-trips maintain correct ordering
 *  15.  redo stack is cleared on new push
 */
class UndoStackTest {

    // -----------------------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------------------

    /** Simple mutable cell used as "domain state" in tests. */
    private class Cell(var value: Int = 0)

    /**
     * Builds an [UndoStack.Entry] that increments [cell] on apply and
     * decrements on reverse.
     */
    private fun incrementEntry(
        cell: Cell,
        auditDescription: String = "increment cell",
        compensatingSync: (suspend () -> Boolean)? = null,
    ): UndoStack.Entry<String> = UndoStack.Entry(
        payload = "increment",
        apply = { cell.value += 1 },
        reverse = { cell.value -= 1 },
        auditDescription = auditDescription,
        compensatingSync = compensatingSync,
    )

    // -----------------------------------------------------------------------
    // 1. push + undo restores state
    // -----------------------------------------------------------------------

    @Test
    fun `push followed by undo restores prior domain state`() = runBlocking {
        val cell = Cell(10)
        val stack = UndoStack<String>()
        val entry = incrementEntry(cell)

        cell.value += 1 // caller applies optimistically
        stack.push(entry)
        assertEquals(11, cell.value)

        val result = stack.undo()

        assertTrue(result)
        assertEquals(10, cell.value)
    }

    // -----------------------------------------------------------------------
    // 2. redo after undo re-applies action
    // -----------------------------------------------------------------------

    @Test
    fun `redo after undo re-applies the action`() = runBlocking {
        val cell = Cell(0)
        val stack = UndoStack<String>()
        val entry = incrementEntry(cell)

        cell.value += 1
        stack.push(entry)
        stack.undo()
        assertEquals(0, cell.value)

        val result = stack.redo()

        assertTrue(result)
        assertEquals(1, cell.value)
    }

    // -----------------------------------------------------------------------
    // 3. push clears redo stack
    // -----------------------------------------------------------------------

    @Test
    fun `push after undo clears redo stack`() = runBlocking {
        val cell = Cell(0)
        val stack = UndoStack<String>()

        cell.value += 1
        stack.push(incrementEntry(cell))
        stack.undo()
        assertTrue("canRedo should be true after undo", stack.canRedo.value)

        // New push should clear redo
        cell.value += 1
        stack.push(incrementEntry(cell))

        assertFalse("canRedo must be false after a new push", stack.canRedo.value)
        val redoResult = stack.redo()
        assertFalse("redo on now-empty redo stack must return false", redoResult)
    }

    // -----------------------------------------------------------------------
    // 4. stack depth capped at maxDepth; oldest entry dropped
    // -----------------------------------------------------------------------

    @Test
    fun `oldest entry dropped when stack exceeds maxDepth`() = runBlocking {
        val maxDepth = 3
        val stack = UndoStack<Int>(maxDepth = maxDepth)

        // Push maxDepth + 1 entries
        for (i in 1..(maxDepth + 1)) {
            stack.push(
                UndoStack.Entry(
                    payload = i,
                    apply = {},
                    reverse = {},
                    auditDescription = "action-$i",
                )
            )
        }

        assertTrue(stack.canUndo.value)
        assertFalse(stack.canRedo.value)

        // Undo all surviving entries (should be exactly maxDepth)
        repeat(maxDepth) { stack.undo() }

        // Stack should now be empty — the oldest entry was dropped
        assertFalse("Stack should be empty after undoing all capped entries", stack.canUndo.value)

        // One further undo must return false
        val extraUndo = stack.undo()
        assertFalse("No further undo should be possible once empty", extraUndo)
    }

    @Test
    fun `maxDepth=1 keeps only the most recent entry`() = runBlocking {
        val cell = Cell(0)
        val stack = UndoStack<String>(maxDepth = 1)

        // Push two entries: second should evict first
        cell.value += 1
        stack.push(incrementEntry(cell, auditDescription = "first"))
        cell.value += 1
        stack.push(incrementEntry(cell, auditDescription = "second"))

        // Only one undo available
        assertTrue(stack.canUndo.value)
        stack.undo()
        assertFalse("Only one entry should survive with maxDepth=1", stack.canUndo.value)
    }

    // -----------------------------------------------------------------------
    // 5. canUndo / canRedo StateFlows emit correctly
    // -----------------------------------------------------------------------

    @Test
    fun `canUndo and canRedo reflect stack state after each operation`() = runBlocking {
        val cell = Cell(0)
        val stack = UndoStack<String>()

        assertFalse("canUndo initially false", stack.canUndo.value)
        assertFalse("canRedo initially false", stack.canRedo.value)

        cell.value += 1
        stack.push(incrementEntry(cell))
        assertTrue("canUndo true after push", stack.canUndo.value)
        assertFalse("canRedo false after push", stack.canRedo.value)

        stack.undo()
        assertFalse("canUndo false after undo", stack.canUndo.value)
        assertTrue("canRedo true after undo", stack.canRedo.value)

        stack.redo()
        assertTrue("canUndo true after redo", stack.canUndo.value)
        assertFalse("canRedo false after redo", stack.canRedo.value)

        stack.clear()
        assertFalse("canUndo false after clear", stack.canUndo.value)
        assertFalse("canRedo false after clear", stack.canRedo.value)
    }

    // -----------------------------------------------------------------------
    // 6. undo() fires reverse lambda and emits UndoEvent.Undone
    // -----------------------------------------------------------------------

    @Test
    fun `undo fires reverse lambda and emits UndoEvent_Undone with auditDescription`() = runBlocking {
        val cell = Cell(5)
        val stack = UndoStack<String>()
        val entry = incrementEntry(cell, auditDescription = "bump")

        cell.value += 1
        stack.push(entry)

        // Step 1: start the collector FIRST, then yield so it registers as subscriber.
        val eventDeferred = async {
            stack.events.take(1).toList()
        }
        // Step 2: yield so the async coroutine starts and subscribes to events.
        yield()

        // Step 3: trigger the action; the event lands in the subscriber's buffer.
        stack.undo()

        // Step 4: await the result.
        val events = eventDeferred.await()
        assertEquals(5, cell.value) // cell was 5, incremented to 6, undone back to 5
        assertEquals(1, events.size)
        val undoneEvent = events.first() as UndoStack.UndoEvent.Undone<String>
        assertEquals("bump", undoneEvent.entry.auditDescription)
    }

    // -----------------------------------------------------------------------
    // 7. compensatingSync is invoked on undo when present
    // -----------------------------------------------------------------------

    @Test
    fun `compensatingSync lambda is called during undo`() = runBlocking {
        var syncCalled = false
        val cell = Cell(0)
        val entry = UndoStack.Entry(
            payload = "sync-test",
            apply = { cell.value += 1 },
            reverse = { cell.value -= 1 },
            auditDescription = "sync action",
            compensatingSync = {
                syncCalled = true
                true // success
            },
        )
        val stack = UndoStack<String>()
        cell.value += 1
        stack.push(entry)

        val result = stack.undo()

        assertTrue(result)
        assertTrue("compensatingSync must have been called", syncCalled)
        assertEquals(0, cell.value)
    }

    // -----------------------------------------------------------------------
    // 8. compensatingSync returning false → Failed event, stack unchanged
    // -----------------------------------------------------------------------

    @Test
    fun `undo with failing compensatingSync emits Failed and leaves stack unchanged`() = runBlocking {
        val cell = Cell(0)
        val entry = UndoStack.Entry(
            payload = "sync-fail",
            apply = { cell.value += 1 },
            reverse = { cell.value -= 1 },
            auditDescription = "server-synced action",
            compensatingSync = { false }, // server refuses
        )
        val stack = UndoStack<String>()
        cell.value += 1
        stack.push(entry)

        // Subscribe before triggering, then yield so collector starts.
        val eventDeferred = async {
            stack.events.take(1).toList()
        }
        yield() // let collector register as subscriber

        val result = stack.undo()

        val events = eventDeferred.await()
        assertFalse("undo must return false when compensation fails", result)
        assertEquals("Cell must be unchanged when undo fails", 1, cell.value)
        assertTrue("canUndo must still be true", stack.canUndo.value)
        assertFalse("canRedo must remain false", stack.canRedo.value)

        assertEquals(1, events.size)
        val failedEvent = events.first() as UndoStack.UndoEvent.Failed<String>
        assertEquals("Can't undo — action already processed", failedEvent.reason)
        assertEquals("server-synced action", failedEvent.entry.auditDescription)
    }

    // -----------------------------------------------------------------------
    // 9. clear() empties both stacks and resets canUndo/canRedo to false
    // -----------------------------------------------------------------------

    @Test
    fun `clear empties undo and redo stacks`() = runBlocking {
        val cell = Cell(0)
        val stack = UndoStack<String>()

        cell.value += 1
        stack.push(incrementEntry(cell))
        cell.value += 1
        stack.push(incrementEntry(cell))
        stack.undo()

        assertTrue(stack.canUndo.value)
        assertTrue(stack.canRedo.value)

        stack.clear()

        assertFalse("canUndo must be false after clear", stack.canUndo.value)
        assertFalse("canRedo must be false after clear", stack.canRedo.value)

        val undoResult = stack.undo()
        val redoResult = stack.redo()
        assertFalse("undo on cleared stack returns false", undoResult)
        assertFalse("redo on cleared stack returns false", redoResult)
    }

    // -----------------------------------------------------------------------
    // 10. undo() on empty stack returns false (no crash)
    // -----------------------------------------------------------------------

    @Test
    fun `undo on empty stack returns false without throwing`() = runBlocking {
        val stack = UndoStack<String>()
        val result = stack.undo()
        assertFalse(result)
    }

    // -----------------------------------------------------------------------
    // 11. redo() on empty stack returns false (no crash)
    // -----------------------------------------------------------------------

    @Test
    fun `redo on empty stack returns false without throwing`() = runBlocking {
        val stack = UndoStack<String>()
        val result = stack.redo()
        assertFalse(result)
    }

    // -----------------------------------------------------------------------
    // 12. events SharedFlow has replay=0 (late subscriber misses prior events)
    // -----------------------------------------------------------------------

    @Test
    fun `late subscriber does not receive past events (replay=0)`() = runBlocking {
        val cell = Cell(0)
        val stack = UndoStack<String>()

        // Push and undo BEFORE subscribing — events are emitted with no subscriber
        // and are therefore dropped (replay=0 means no cache; the buffer only helps
        // slow existing subscribers, not late-arriving ones).
        cell.value += 1
        stack.push(incrementEntry(cell))
        stack.undo()

        // Now subscribe to the events flow.  With replay=0 no cached events
        // should be delivered.  We set up a Channel-based collector and check
        // it receives nothing within the same coroutine turn.
        val received = Channel<UndoStack.UndoEvent<String>>(capacity = Channel.UNLIMITED)
        val collectorJob = launch {
            stack.events.collect { received.send(it) }
        }

        // Yield so the collector coroutine gets a chance to run and receive any
        // replayed events (there should be none).
        yield()

        val item = received.tryReceive().getOrNull()
        collectorJob.cancel()

        assertNull(
            "Late subscriber must not receive past events with replay=0",
            item,
        )
    }

    // -----------------------------------------------------------------------
    // 13. auditDescription present on every event type
    // -----------------------------------------------------------------------

    @Test
    fun `every event carries a non-blank auditDescription`() = runBlocking {
        val cell = Cell(0)
        val stack = UndoStack<String>()

        // We expect 3 events: Pushed, Undone, Redone.
        // Yield after async start so the collector registers as subscriber BEFORE
        // we trigger the actions (otherwise tryEmit fires before subscriber exists
        // and events are dropped, leaving take(3) waiting forever).
        val eventsDeferred = async {
            stack.events.take(3).toList()
        }
        yield() // let collector register as subscriber

        cell.value += 1
        stack.push(incrementEntry(cell, auditDescription = "audit: push"))
        stack.undo()
        stack.redo()

        val events = eventsDeferred.await()

        assertEquals("Expected 3 events (Pushed, Undone, Redone)", 3, events.size)
        for (event in events) {
            val desc = when (event) {
                is UndoStack.UndoEvent.Pushed -> event.entry.auditDescription
                is UndoStack.UndoEvent.Undone -> event.entry.auditDescription
                is UndoStack.UndoEvent.Redone -> event.entry.auditDescription
                is UndoStack.UndoEvent.Failed -> event.entry.auditDescription
            }
            assertTrue(
                "auditDescription must not be blank on event $event",
                desc.isNotBlank(),
            )
        }
    }

    // -----------------------------------------------------------------------
    // 14. multiple undo/redo round-trips maintain correct ordering
    // -----------------------------------------------------------------------

    @Test
    fun `multiple undo redo round trips maintain correct domain state`() = runBlocking {
        val cell = Cell(0)
        val stack = UndoStack<String>()

        repeat(3) {
            cell.value += 1
            stack.push(incrementEntry(cell, auditDescription = "step ${it + 1}"))
        }
        assertEquals(3, cell.value)

        // Undo all three
        repeat(3) { stack.undo() }
        assertEquals(0, cell.value)
        assertFalse(stack.canUndo.value)
        assertTrue(stack.canRedo.value)

        // Redo all three
        repeat(3) { stack.redo() }
        assertEquals(3, cell.value)
        assertTrue(stack.canUndo.value)
        assertFalse(stack.canRedo.value)
    }

    // -----------------------------------------------------------------------
    // 15. redo stack is cleared on new push (branching abandons redo history)
    // -----------------------------------------------------------------------

    @Test
    fun `redo history is abandoned after a new push branches off`() = runBlocking {
        val cell = Cell(0)
        val stack = UndoStack<String>()

        cell.value += 1
        stack.push(incrementEntry(cell, auditDescription = "original"))
        stack.undo()
        assertEquals(0, cell.value)
        assertTrue("redo should be available before branch", stack.canRedo.value)

        // Branch: new push clears the redo stack
        cell.value += 5
        stack.push(
            UndoStack.Entry(
                payload = "branch",
                apply = { cell.value += 5 },
                reverse = { cell.value -= 5 },
                auditDescription = "branch action",
            )
        )

        assertFalse("redo history must be gone after branching push", stack.canRedo.value)
        val redoResult = stack.redo()
        assertFalse("redo must return false with empty redo stack", redoResult)

        // Undo the branch entry to confirm it is the only entry on stack
        stack.undo()
        assertEquals(0, cell.value)
        assertFalse("No more entries to undo after branch was undone", stack.canUndo.value)
    }
}
