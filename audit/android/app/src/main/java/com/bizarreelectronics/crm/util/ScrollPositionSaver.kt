package com.bizarreelectronics.crm.util

import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.lifecycle.SavedStateHandle

// ---------------------------------------------------------------------------
// §75.5 Scroll-position preservation on back-navigation and process death
// ---------------------------------------------------------------------------
//
// ## Problem
// Every primary list screen calls `rememberLazyListState()` which restores scroll
// across configuration changes (rotation) because `rememberLazyListState` is
// backed by Compose's saved-instance-state machinery *within* the composition.
// However, when the user navigates forward (e.g. Ticket list → Ticket detail)
// and then presses back, the nav back-stack pops the detail *destination* but
// the **composition** of the list screen was never destroyed — it was kept in the
// back-stack.  On most devices this already works.  The gap is:
//
//  1. **Process death + restore**: the OS kills the process; the user returns;
//     Compose re-creates the nav graph from the SavedStateRegistry.  Scroll
//     state is NOT part of the nav-graph bundle unless explicitly saved there.
//
//  2. **Multi-module / conditional nav**: some routes recreate compositions on
//     the way back (e.g. two-pane adaptive layout resizing).  Without explicit
//     saving the list snaps to 0.
//
// ## Solution
// `rememberSaveableLazyListState` wraps `rememberSaveable` with a custom
// `Saver` that bundles `(firstVisibleItemIndex, firstVisibleItemScrollOffset)`.
// Because it uses `rememberSaveable`, the position survives:
//   - Rotation / config change (already works with plain rememberLazyListState)
//   - Back-nav when the composition was destroyed (the saved state is in the
//     Activity's saved instance state → NavBackStackEntry → rememberSaveable)
//   - Process death → onSaveInstanceState → restore (the Int pair is a bundle-
//     compatible primitive, no custom parcelling required)
//
// For an extra durability layer, `LazyListState.saveToHandle` and
// `SavedStateHandle.restoreScrollPosition` mirror the same two integers into
// a ViewModel's [SavedStateHandle].  ViewModels inject SSH and call these once
// on init / on dispose so the last scroll position is preserved even when the
// list composable has never been reattached (e.g. cold-start with deep-link
// straight to a detail, then back — the list is freshly created and should
// scroll to where the user was before the deep-link).
//
// ## Usage — screen composable
// ```kotlin
// val listState = rememberSaveableLazyListState(key = "ticket_list_scroll")
// ```
//
// ## Usage — ViewModel (optional extra durability)
// ```kotlin
// // In init:
// val (idx, off) = savedStateHandle.restoreScrollPosition("ticket_list")
// // Exposed to the screen as StateFlow<ScrollPosition>:
// val scrollPosition = MutableStateFlow(ScrollPosition(idx, off))
//
// // Called by the screen via DisposableEffect(Unit) { onDispose { vm.saveScroll(listState) } }
// fun saveScrollPosition(index: Int, offset: Int) {
//     savedStateHandle.saveScrollPosition("ticket_list", index, offset)
// }
// ```

// ---------------------------------------------------------------------------
// Data holder
// ---------------------------------------------------------------------------

/**
 * Lightweight snapshot of a [LazyListState] scroll position.
 * Both values are Parcelable-primitive (Int), so they survive bundle round-trips
 * without any `@Parcelize` annotation.
 */
@Immutable
data class ScrollPosition(
    val firstVisibleItemIndex: Int = 0,
    val firstVisibleItemScrollOffset: Int = 0,
) {
    companion object {
        val Zero = ScrollPosition()
    }
}

// ---------------------------------------------------------------------------
// Compose-layer saver
// ---------------------------------------------------------------------------

/**
 * A [Saver] for [LazyListState] that persists the first-visible-item index and
 * its pixel scroll offset.  Stored as a two-element [IntArray] so that the
 * value is bundle-compatible without additional serialisation.
 */
private val LazyListStateSaver: Saver<LazyListState, IntArray> = Saver(
    save = { state ->
        intArrayOf(
            state.firstVisibleItemIndex,
            state.firstVisibleItemScrollOffset,
        )
    },
    restore = { saved ->
        LazyListState(
            firstVisibleItemIndex = saved[0],
            firstVisibleItemScrollOffset = saved[1],
        )
    },
)

/**
 * Remembers a [LazyListState] whose scroll position is automatically saved and
 * restored across:
 *  - Rotation / config changes (same as plain `rememberLazyListState`)
 *  - Navigation back-stack restores (saved in the NavBackStackEntry's
 *    saved-instance-state bundle via Compose's `rememberSaveable`)
 *  - Process death + Activity recreation (same bundle, written to
 *    `onSaveInstanceState`)
 *
 * @param key Unique key within the composition; useful when the same screen
 *   holds multiple lists (e.g. tabbed views).  Passed as a positional input to
 *   `rememberSaveable` (not the deprecated `key` named parameter) so that each
 *   unique string results in a distinct saved-state slot.
 * @param initialIndex  Seed index used only on **first** composition (no saved
 *   state exists yet).  Typically `0`.
 * @param initialOffset Seed pixel offset used only on first composition.
 */
@Composable
fun rememberSaveableLazyListState(
    key: String = "",
    initialIndex: Int = 0,
    initialOffset: Int = 0,
): LazyListState = rememberSaveable(
    key,           // positional input — unique per list, avoids state collision
    saver = LazyListStateSaver,
) {
    LazyListState(
        firstVisibleItemIndex = initialIndex,
        firstVisibleItemScrollOffset = initialOffset,
    )
}

// ---------------------------------------------------------------------------
// SavedStateHandle extensions — ViewModel-layer durability
// ---------------------------------------------------------------------------

private fun scrollIndexKey(scope: String) = "${scope}_scroll_idx"
private fun scrollOffsetKey(scope: String) = "${scope}_scroll_off"

/**
 * Reads a previously-persisted [ScrollPosition] from [SavedStateHandle].
 *
 * Returns [ScrollPosition.Zero] if nothing has been stored yet (fresh launch
 * or after the user cleared app data).
 *
 * @param scope Logical name for the screen / list, e.g. `"ticket_list"`.
 *   Used as a key prefix so multiple ViewModels can share the same SSH without
 *   collision.
 */
fun SavedStateHandle.restoreScrollPosition(scope: String): ScrollPosition {
    val idx = get<Int>(scrollIndexKey(scope)) ?: 0
    val off = get<Int>(scrollOffsetKey(scope)) ?: 0
    return ScrollPosition(idx, off)
}

/**
 * Persists a [ScrollPosition] into [SavedStateHandle] so it survives process
 * death.  Call this from a `DisposableEffect(Unit) { onDispose { … } }` in
 * the composable, or from `ViewModel.onCleared`.
 *
 * @param scope Logical name matching the one passed to [restoreScrollPosition].
 * @param position Current scroll position snapshot.
 */
fun SavedStateHandle.saveScrollPosition(scope: String, position: ScrollPosition) {
    set(scrollIndexKey(scope), position.firstVisibleItemIndex)
    set(scrollOffsetKey(scope), position.firstVisibleItemScrollOffset)
}

// ---------------------------------------------------------------------------
// Compose-side disposal helper
// ---------------------------------------------------------------------------

/**
 * A [DisposableEffect] that saves the current [LazyListState] scroll position
 * into [SavedStateHandle] when the composable leaves the composition (e.g.
 * navigation forward).  This complements [rememberSaveableLazyListState] with
 * ViewModel-level durability.
 *
 * ## Usage
 * ```kotlin
 * val listState = rememberSaveableLazyListState("tickets")
 *
 * SaveScrollOnDispose(
 *     listState  = listState,
 *     handle     = viewModel.savedStateHandle,   // must be @VisibleForTesting or exposed
 *     scope      = "ticket_list",
 * )
 * ```
 *
 * If your ViewModel exposes a `fun saveScrollPosition(pos: ScrollPosition)` method
 * instead of the raw handle, call that directly inside the `DisposableEffect`.
 */
@Composable
fun SaveScrollOnDispose(
    listState: LazyListState,
    onSave: (ScrollPosition) -> Unit,
) {
    DisposableEffect(Unit) {
        onDispose {
            onSave(
                ScrollPosition(
                    firstVisibleItemIndex = listState.firstVisibleItemIndex,
                    firstVisibleItemScrollOffset = listState.firstVisibleItemScrollOffset,
                ),
            )
        }
    }
}
