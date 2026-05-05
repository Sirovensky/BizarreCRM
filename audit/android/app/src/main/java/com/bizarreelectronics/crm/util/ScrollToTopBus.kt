package com.bizarreelectronics.crm.util

import androidx.compose.runtime.compositionLocalOf
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import javax.inject.Inject
import javax.inject.Singleton

/**
 * §75.5 — Jump-to-top on bottom-nav re-select.
 *
 * When the user taps a bottom-nav tab that is already selected, every primary
 * list screen subscribed for that route receives a one-shot signal to animate
 * its scroll position back to the top.  This matches the canonical iOS / web
 * UX pattern (re-tap tab → scroll to top).
 *
 * ## Design
 * - [MutableSharedFlow] with `extraBufferCapacity = 1` so the emit never
 *   suspends (called from an onClick lambda, not a coroutine scope).
 * - `replay = 0` so a late subscriber (e.g. screen recomposed after rotation)
 *   does NOT receive a stale re-select event from before it was visible.
 *
 * ## Usage — emitter side (AppNavGraph)
 * ```
 * // Inside NavigationBarItem onClick, when isSelected && same tab tapped:
 * scrollToTopBus.requestScrollToTop(item.screen.route)
 * ```
 *
 * ## Usage — consumer side (list screens)
 * ```
 * val listState = rememberLazyListState()
 * val scope = rememberCoroutineScope()
 * val bus = LocalScrollToTopBus.current
 * LaunchedEffect(bus) {
 *     bus?.events?.collect { route ->
 *         if (route == Screen.Tickets.route) {
 *             scope.launch { listState.animateScrollToItem(0) }
 *         }
 *     }
 * }
 * ```
 *
 * Injected as a Hilt [Singleton] so [com.bizarreelectronics.crm.MainActivity]
 * can pass it into [AppNavGraph] at the call site alongside [DeepLinkBus].
 */
@Singleton
class ScrollToTopBus @Inject constructor() {

    private val _events = MutableSharedFlow<String>(
        replay = 0,
        extraBufferCapacity = 1,
    )

    /**
     * Emits the [route] of the tab whose list should scroll to the top.
     * Fire-and-forget: drops the event if no collector is active (
     * `tryEmit` returns false rather than blocking).
     */
    fun requestScrollToTop(route: String) {
        _events.tryEmit(route)
    }

    /**
     * Collected by primary list screens to trigger a scroll-to-top animation
     * when the user re-selects the tab they are already viewing.
     */
    val events: SharedFlow<String> = _events.asSharedFlow()
}

/**
 * CompositionLocal that makes [ScrollToTopBus] available to any composable
 * inside [AppNavGraph] without threading it through every call site.
 *
 * Defaults to `null` so previews and tests that don't provide a bus
 * gracefully no-op (the `?.events?.collect` check in screens is a safe call).
 */
val LocalScrollToTopBus = compositionLocalOf<ScrollToTopBus?> { null }
