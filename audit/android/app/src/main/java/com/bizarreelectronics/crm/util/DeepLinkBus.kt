package com.bizarreelectronics.crm.util

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject
import javax.inject.Singleton

/** Carries the code + state pair from a `bizarrecrm://sso/callback` deep link. */
data class SsoResult(val code: String, val state: String)

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

    // §2.20 L446 — SSO callback bus.
    //
    // MainActivity.resolveDeepLink recognises `bizarrecrm://sso/callback` and
    // calls [publishSsoResult] with the extracted code + state.
    // LoginViewModel collects from [pendingSsoResult] and dispatches token exchange.
    // Consumers MUST call [consumeSsoResult] after processing.

    private val _pendingSsoResult = MutableStateFlow<SsoResult?>(null)

    /** Collected by LoginViewModel to exchange the SSO authorization code for tokens. */
    val pendingSsoResult: StateFlow<SsoResult?> = _pendingSsoResult.asStateFlow()

    /** Called by MainActivity when `bizarrecrm://sso/callback` is received. */
    fun publishSsoResult(code: String, state: String) {
        _pendingSsoResult.value = SsoResult(code, state)
    }

    /** Called by the ViewModel after [pendingSsoResult] has been processed. */
    fun consumeSsoResult() {
        _pendingSsoResult.value = null
    }

    // §2.21 L454 — Magic-link token bus.
    //
    // MainActivity.resolveDeepLink recognises both:
    //   https://app.bizarrecrm.com/magic/<token>   (HTTPS App Link)
    //   bizarrecrm://magic/<token>                  (custom scheme)
    // After DeepLinkAllowlist validates the token shape, MainActivity calls
    // [publishMagicLinkToken] and returns null (no nav route — VM handles it).
    // LoginViewModel collects from [pendingMagicToken] and dispatches the
    // phishing-defense preview + exchange call.
    // Consumers MUST call [consumeMagicToken] after processing.

    private val _pendingMagicToken = MutableStateFlow<String?>(null)

    /** Collected by LoginViewModel to exchange a magic-link token for session tokens. */
    val pendingMagicToken: StateFlow<String?> = _pendingMagicToken.asStateFlow()

    /** Called by MainActivity when a magic-link URI is received. */
    fun publishMagicLinkToken(token: String) {
        _pendingMagicToken.value = token
    }

    /** Called by the ViewModel after [pendingMagicToken] has been processed. */
    fun consumeMagicToken() {
        _pendingMagicToken.value = null
    }

    // §2.15 L387-L388 — Forgot-PIN reset-token bus.
    //
    // MainActivity.resolveDeepLink recognises:
    //   bizarrecrm://forgot-pin/<token>
    // After DeepLinkAllowlist validates the token shape, MainActivity calls
    // [publishForgotPinToken] and returns null (no nav route — ForgotPinViewModel
    // collects and advances to the SettingPin state).
    // Consumers MUST call [consumeForgotPinToken] after processing.

    private val _pendingForgotPinToken = MutableStateFlow<String?>(null)

    /** Collected by ForgotPinViewModel to redeem the PIN-reset token. */
    val pendingForgotPinToken: StateFlow<String?> = _pendingForgotPinToken.asStateFlow()

    /**
     * Called by MainActivity when a `bizarrecrm://forgot-pin/<token>` URI is received.
     * [token] has already been validated by [DeepLinkAllowlist.validateForgotPinToken].
     */
    fun publishForgotPinToken(token: String) {
        _pendingForgotPinToken.value = token
    }

    /** Called by ForgotPinViewModel after [pendingForgotPinToken] has been processed. */
    fun consumeForgotPinToken() {
        _pendingForgotPinToken.value = null
    }

    // §68.3 — Auth-required deep link queuing.
    //
    // When a `bizarrecrm://` or HTTPS App Link arrives and the user is NOT yet
    // authenticated, the route is queued here instead of being dropped.
    // AppNavGraph's deep-link LaunchedEffect checks isLoggedIn; on transition
    // to logged-in it re-publishes the queued route via [publish] so the user
    // lands on their intended destination after sign-in. This mirrors the
    // `intent_after_login` pattern described in §68.3.
    //
    // Callers MUST call [consumePendingAfterLogin] after the queued route
    // has been published for nav-graph consumption, otherwise a subsequent
    // login event (e.g. forced re-auth on session expiry) would re-fire it.

    private val _pendingRouteAfterLogin = MutableStateFlow<String?>(null)

    /** Queued deep-link route that arrived while the user was not logged in. */
    val pendingRouteAfterLogin: StateFlow<String?> = _pendingRouteAfterLogin.asStateFlow()

    /**
     * Queue [route] to be navigated to immediately after the user successfully
     * signs in. Null is a no-op. Replaces any previously queued route — only
     * the most-recent intent is honoured (last-tap-wins, avoids stale queues).
     */
    fun queueAfterLogin(route: String?) {
        if (route == null) return
        _pendingRouteAfterLogin.value = route
    }

    /** Clear the post-login queue entry after it has been dispatched. */
    fun consumePendingAfterLogin() {
        _pendingRouteAfterLogin.value = null
    }

    // §25.2 Inbound-share bus.
    //
    // When another app shares content to BizarreCRM via ACTION_SEND /
    // ACTION_SEND_MULTIPLE, MainActivity.resolveInboundShare() calls
    // [publishInboundShare] with the action + MIME type. The Tickets list
    // screen (or a future dedicated picker) collects from [pendingInboundShare]
    // and shows the "Attach to ticket / New note" bottom sheet.
    // The original Intent remains accessible via Activity.getIntent() at the
    // call site; only the (action, mimeType) pair is carried here.
    // Consumers MUST call [consumeInboundShare] after processing.

    data class InboundShare(val action: String, val mimeType: String)

    private val _pendingInboundShare = MutableStateFlow<InboundShare?>(null)

    /** Collected by the Tickets list or dedicated inbound-share picker composable. */
    val pendingInboundShare: StateFlow<InboundShare?> = _pendingInboundShare.asStateFlow()

    /** Called by MainActivity when an ACTION_SEND / ACTION_SEND_MULTIPLE intent arrives. */
    fun publishInboundShare(action: String, mimeType: String) {
        _pendingInboundShare.value = InboundShare(action, mimeType)
    }

    /** Called after [pendingInboundShare] has been handled by the UI. */
    fun consumeInboundShare() {
        _pendingInboundShare.value = null
    }
}
