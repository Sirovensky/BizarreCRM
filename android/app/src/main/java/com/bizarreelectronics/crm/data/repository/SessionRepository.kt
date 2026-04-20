package com.bizarreelectronics.crm.data.repository

import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.remote.api.AuthApi
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject
import javax.inject.Singleton

/**
 * §2.11 Session bootstrap.
 *
 * Calls `GET /auth/me` once on cold-start when a session token is present
 * to confirm the token is still valid + to pull the latest user identity
 * (role, permissions, store name) into [AuthPreferences]. Keeps the rest of
 * the app from rendering stale role-based UI when the user's permissions
 * have changed server-side since the last sign-in.
 *
 * The call is fire-and-forget: a 401 triggers `AuthPreferences.clear()`
 * which drops the user back to login through the existing
 * `authPreferences.authCleared` SharedFlow observer in the nav graph.
 */
@Singleton
class SessionRepository @Inject constructor(
    private val authApi: AuthApi,
    private val authPreferences: AuthPreferences,
) {
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    enum class State { Idle, Bootstrapping, Ready, Failed }

    private val _state = MutableStateFlow(State.Idle)
    val state: StateFlow<State> = _state.asStateFlow()

    /**
     * Fire-and-forget bootstrap. Safe to call repeatedly — concurrent calls
     * are no-ops once the first is in flight.
     */
    fun bootstrap() {
        if (!authPreferences.isLoggedIn) return
        if (_state.value == State.Bootstrapping) return
        _state.value = State.Bootstrapping
        scope.launch { runBootstrap() }
    }

    private suspend fun runBootstrap() {
        val response = try {
            authApi.getMe()
        } catch (t: Throwable) {
            _state.value = State.Failed
            return
        }
        if (!response.success) {
            _state.value = State.Failed
            // 401 inside the response envelope is rare — the OkHttp authenticator
            // already replays + then clears auth on refresh failure. Still, if
            // the server returns success=false with no token issue, we just stay
            // signed in and let the next user action fail with a more specific
            // error.
            return
        }
        val user = response.data ?: run {
            _state.value = State.Failed
            return
        }
        // Refresh the cached identity bits so role / store / display name
        // stay up to date without forcing a re-login.
        authPreferences.userId = user.id
        authPreferences.username = user.username
        user.firstName?.let { authPreferences.userFirstName = it }
        user.lastName?.let { authPreferences.userLastName = it }
        authPreferences.userRole = user.role
        _state.value = State.Ready
    }
}
