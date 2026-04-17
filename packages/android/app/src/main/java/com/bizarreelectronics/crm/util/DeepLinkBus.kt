package com.bizarreelectronics.crm.util

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject
import javax.inject.Singleton

/**
 * AND-20260414-H1: single-writer / single-reader handoff for deep-link
 * routes resolved in [com.bizarreelectronics.crm.MainActivity].
 *
 * MainActivity owns the Intent (launcher shortcut, App Actions capability,
 * `bizarrecrm://` URI, or the Quick Settings tile) and extracts a route
 * string like `ticket/new`, `customer/new`, or `scan`. The nav graph lives
 * inside a composable that can't reach back into the Activity directly,
 * so the Activity emits into this Hilt-scoped bus and the nav graph
 * collects from it via a [androidx.compose.runtime.LaunchedEffect].
 *
 * Why `MutableStateFlow<String?>` and not `SharedFlow`:
 * - Cold-start: the value is published BEFORE the nav graph is composed.
 *   A SharedFlow with replay=0 would drop that emission; StateFlow keeps
 *   it pending until the first collector arrives.
 * - Warm-start via [com.bizarreelectronics.crm.MainActivity.onNewIntent]:
 *   we overwrite the value, the collector runs again, and the consumer
 *   calls [consume] to null the state back out so rotation / recomposition
 *   doesn't re-navigate to the same screen.
 *
 * Consumers MUST call [consume] once the navigation has been dispatched,
 * otherwise every future recomposition will re-fire the navigate call.
 */
@Singleton
class DeepLinkBus @Inject constructor() {

    private val _pendingRoute = MutableStateFlow<String?>(null)

    /** Collected by the nav graph; emits the raw deep-link route or null. */
    val pendingRoute: StateFlow<String?> = _pendingRoute.asStateFlow()

    /**
     * Publish a resolved deep-link route for the nav graph to pick up.
     * Null is a no-op — callers pass the result of their whitelist check
     * straight through, so filtering stays in one place (MainActivity).
     */
    fun publish(route: String?) {
        if (route == null) return
        _pendingRoute.value = route
    }

    /**
     * Called by the nav graph after [pendingRoute] has been navigated to.
     * Clears the state so a configuration change (rotation, dark-mode
     * toggle) doesn't cause the route to fire a second time.
     */
    fun consume() {
        _pendingRoute.value = null
    }
}
