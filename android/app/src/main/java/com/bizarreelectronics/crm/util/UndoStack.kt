package com.bizarreelectronics.crm.util

import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Reusable undo/redo stack for optimistic-write flows (§1 lines 231-236).
 *
 * A ViewModel holds one `UndoStack<Action>` instance, where `Action` is a
 * feature-specific sealed type carrying the before/after data. Push an action
 * after applying it optimistically. Call [undo] to pop and invoke the reverse;
 * call [redo] to re-apply the most recently undone action.
 *
 * ### Stack semantics
 * - Stack depth is capped at [maxDepth] (default 50, per line 231). Exceeding
 *   the cap drops the **oldest** entry so the most recent work is always
 *   undoable.
 * - Pushing a new entry clears the redo stack (classic linear undo semantics —
 *   branching off the current head abandons redo history).
 * - [clear] empties both stacks, intended for navigation-dismiss events (line 231).
 *
 * ### Server-sync contract (line 235)
 * Each [Entry] may carry a [Entry.compensatingSync] suspend lambda. When
 * present, [undo] invokes it before declaring success. A `false` return means
 * the server refused compensation (action already processed). In that case
 * [undo] emits [UndoEvent.Failed] with the message "Can't undo — action already
 * processed", leaves the stack **unchanged**, and returns `false` so the UI can
 * show the toast.
 *
 * ### Audit contract (line 236)
 * Every successful [undo] emits [UndoEvent.Undone] and every successful [redo]
 * emits [UndoEvent.Redone], both carrying [Entry.auditDescription]. The caller
 * forwards these to AuditRepository — undo is never silent.
 *
 * ### Threading
 * Single-writer assumed (ViewModel main-scope coroutine). No Mutex is used;
 * all mutations run on the caller's coroutine context. If multi-thread access
 * is ever needed, wrap with `Mutex` and `withLock`.
 *
 * ### Compose integration
 * [canUndo] and [canRedo] are [StateFlow]s safe for `collectAsState()` in
 * Compose. [events] is a [SharedFlow] with `replay = 0` (fire-and-forget).
 *
 * @param T The feature-specific action payload type.
 * @param maxDepth Maximum number of undoable steps retained (default 50).
 */
class UndoStack<T>(val maxDepth: Int = 50) {

    /**
     * A single reversible action on the stack.
     *
     * @param payload            The feature-domain action value (opaque to
     *                           UndoStack; stored for caller use only).
     * @param apply              Lambda that (re-)applies the action. Called by
     *                           [redo]. Must be idempotent with respect to
     *                           domain state when called after a prior [undo].
     * @param reverse            Lambda that reverses the action. Called by
     *                           [undo]. Must restore prior domain state.
     * @param auditDescription   Human-readable description forwarded in every
     *                           [UndoEvent]. Never null or blank.
     * @param compensatingSync   Optional suspend lambda that sends a
     *                           compensating server request when the optimistic
     *                           write was already synced. Returns `true` if
     *                           compensation succeeded, `false` if the server
     *                           refuses (action already processed). If null,
     *                           [undo] proceeds without a server round-trip.
     */
    data class Entry<T>(
        val payload: T,
        val apply: () -> Unit,
        val reverse: () -> Unit,
        val auditDescription: String,
        val compensatingSync: (suspend () -> Boolean)? = null,
    )

    /**
     * Events emitted by [UndoStack] to be forwarded to audit / UI layers.
     *
     * All events carry the [Entry] that triggered them so audit consumers can
     * record [Entry.auditDescription] without extra state lookups.
     */
    sealed class UndoEvent<T> {
        /** Emitted after [push] succeeds. */
        data class Pushed<T>(val entry: Entry<T>) : UndoEvent<T>()

        /**
         * Emitted after a successful [undo]. Carry to AuditRepository so that
         * the undo creates an audit record (never silent, per line 236).
         */
        data class Undone<T>(val entry: Entry<T>) : UndoEvent<T>()

        /**
         * Emitted after a successful [redo]. Carry to AuditRepository — redo
         * is also an auditable mutation.
         */
        data class Redone<T>(val entry: Entry<T>) : UndoEvent<T>()

        /**
         * Emitted when [undo] or [redo] cannot complete. [reason] contains a
         * user-displayable message (e.g., "Can't undo — action already
         * processed" when [Entry.compensatingSync] returns `false`).
         */
        data class Failed<T>(val entry: Entry<T>, val reason: String) : UndoEvent<T>()
    }

    // -----------------------------------------------------------------------
    // Internal state — backed by ArrayDeque for O(1) push/pop at both ends.
    // Both stacks are replaced (never mutated) on every operation to satisfy
    // the immutable-state requirement; the flow emission carries the new value.
    // -----------------------------------------------------------------------

    private var undoStack: ArrayDeque<Entry<T>> = ArrayDeque()
    private var redoStack: ArrayDeque<Entry<T>> = ArrayDeque()

    private val _canUndo = MutableStateFlow(false)
    private val _canRedo = MutableStateFlow(false)

    /** True when there is at least one action that can be undone. */
    val canUndo: StateFlow<Boolean> = _canUndo.asStateFlow()

    /** True when there is at least one action that can be redone. */
    val canRedo: StateFlow<Boolean> = _canRedo.asStateFlow()

    /**
     * Hot event stream. `replay = 0` with `extraBufferCapacity = 16`:
     * - Late subscribers do not receive past events (no replay cache).
     * - `tryEmit()` always completes immediately without suspending because
     *   the buffer absorbs events even before a subscriber is ready.
     * - Suitable for fire-and-forget snackbar / toast triggers in the UI.
     */
    private val _events = MutableSharedFlow<UndoEvent<T>>(
        replay = 0,
        extraBufferCapacity = 16,
    )
    val events: SharedFlow<UndoEvent<T>> = _events.asSharedFlow()

    // -----------------------------------------------------------------------
    // Public API
    // -----------------------------------------------------------------------

    /**
     * Records [entry] as the latest undoable action.
     *
     * The [Entry.apply] lambda **must already have been called** by the caller
     * before pushing — [push] does not re-apply the action; it only records
     * the reverse. Pushing clears the redo stack. If [undoStack] exceeds
     * [maxDepth] after the push, the oldest entry is dropped.
     */
    fun push(entry: Entry<T>) {
        // Rebuild stacks as new objects (immutable-state convention).
        val newUndo = ArrayDeque(undoStack).also { it.addLast(entry) }
        while (newUndo.size > maxDepth) {
            newUndo.removeFirst()
        }
        undoStack = newUndo
        redoStack = ArrayDeque() // clear redo on new push

        syncStateFlows()
        _events.tryEmit(UndoEvent.Pushed(entry))
    }

    /**
     * Pops the most recent action from the undo stack and reverses it.
     *
     * If [Entry.compensatingSync] is non-null, it is invoked first. A `false`
     * return value means the server refused compensation; in that case the
     * stack is left unchanged, [UndoEvent.Failed] is emitted, and this
     * function returns `false`.
     *
     * On success: [Entry.reverse] is called, the entry moves to the redo
     * stack, [UndoEvent.Undone] is emitted, and the function returns `true`.
     *
     * Returns `false` without emitting any event if the undo stack is empty.
     *
     * @return `true` on success, `false` on empty stack or compensation failure.
     */
    suspend fun undo(): Boolean {
        val entry = undoStack.lastOrNull() ?: return false

        // If a compensating server request is needed, attempt it before
        // mutating local state. A false return means "already processed".
        val sync = entry.compensatingSync
        if (sync != null) {
            val compensated = sync()
            if (!compensated) {
                _events.tryEmit(
                    UndoEvent.Failed(
                        entry = entry,
                        reason = "Can't undo — action already processed",
                    ),
                )
                return false
            }
        }

        // Pop from undo, apply reverse, push to redo.
        val newUndo = ArrayDeque(undoStack).also { it.removeLast() }
        val newRedo = ArrayDeque(redoStack).also { it.addLast(entry) }
        undoStack = newUndo
        redoStack = newRedo

        entry.reverse()
        syncStateFlows()
        _events.tryEmit(UndoEvent.Undone(entry))
        return true
    }

    /**
     * Pops the most recently undone action from the redo stack and re-applies it.
     *
     * On success: [Entry.apply] is called, the entry moves back to the undo
     * stack, [UndoEvent.Redone] is emitted, and the function returns `true`.
     *
     * Returns `false` without emitting any event if the redo stack is empty.
     *
     * Note: redo does **not** invoke [Entry.compensatingSync] — the re-apply
     * is a new optimistic write that will be synced via the normal write path.
     *
     * @return `true` on success, `false` on empty redo stack.
     */
    suspend fun redo(): Boolean {
        val entry = redoStack.lastOrNull() ?: return false

        val newRedo = ArrayDeque(redoStack).also { it.removeLast() }
        val newUndo = ArrayDeque(undoStack).also { it.addLast(entry) }
        // Cap undo stack again in case it was at maxDepth.
        while (newUndo.size > maxDepth) {
            newUndo.removeFirst()
        }
        redoStack = newRedo
        undoStack = newUndo

        entry.apply()
        syncStateFlows()
        _events.tryEmit(UndoEvent.Redone(entry))
        return true
    }

    /**
     * Empties both the undo and redo stacks.
     *
     * Call on navigation dismiss to discard in-flight optimistic history that
     * is no longer reachable (line 231: "cleared on nav dismiss").
     */
    fun clear() {
        undoStack = ArrayDeque()
        redoStack = ArrayDeque()
        syncStateFlows()
    }

    // -----------------------------------------------------------------------
    // Internal helpers
    // -----------------------------------------------------------------------

    /** Pushes current stack-size booleans into the StateFlows. */
    private fun syncStateFlows() {
        _canUndo.value = undoStack.isNotEmpty()
        _canRedo.value = redoStack.isNotEmpty()
    }
}
