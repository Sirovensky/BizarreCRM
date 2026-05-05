package com.bizarreelectronics.crm.ui.commandpalette

import androidx.lifecycle.ViewModel
import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject

/**
 * §54 — ViewModel for the command palette overlay.
 *
 * Merges [CommandRegistry.staticCommands] with any [DynamicCommandProvider]
 * implementations injected by Hilt. Filters by the live [query] state and
 * gates admin-only commands against the current user role from [AuthPreferences].
 *
 * §54.3 — recent commands (last [AppPreferences.RECENT_COMMANDS_MAX] activated
 * command IDs) are injected into [CommandRegistry.search] so they surface in the
 * RECENT group at the top of the list on subsequent palette opens.
 *
 * §54.4 — [isEnabled] reflects [AppPreferences.commandPaletteEnabledFlow] so
 * call sites can gate the Ctrl+K / long-press FAB trigger.
 */
@HiltViewModel
class CommandPaletteViewModel @Inject constructor(
    private val authPreferences: AuthPreferences,
    private val appPreferences: AppPreferences,
    private val dynamicProviders: @JvmSuppressWildcards Set<DynamicCommandProvider>,
) : ViewModel() {

    private val _query = MutableStateFlow("")
    val query: StateFlow<String> = _query.asStateFlow()

    private val _results = MutableStateFlow<List<Command>>(emptyList())
    val results: StateFlow<List<Command>> = _results.asStateFlow()

    /** §54.4 — whether the command palette is enabled for the current device/role. */
    val isEnabled: StateFlow<Boolean> = appPreferences.commandPaletteEnabledFlow

    init {
        // Build initial unfiltered list on construction.
        refresh("")
    }

    fun onQueryChange(newQuery: String) {
        _query.value = newQuery
        refresh(newQuery)
    }

    /**
     * §54.3 — Record [commandId] as recently activated and close the palette.
     *
     * Call this instead of [clear] when the user actually executes a command so
     * the MRU list is updated. Persisted to [AppPreferences] for cross-session
     * recency.
     */
    fun onCommandExecuted(commandId: String) {
        appPreferences.addRecentCommandId(commandId)
        clear()
    }

    fun clear() {
        _query.value = ""
        refresh("")
    }

    private fun refresh(query: String) {
        val isAdmin = authPreferences.userRole == "admin"
        val dynamic = dynamicProviders.flatMap { it.provide() }
        _results.value = CommandRegistry.search(
            query = query,
            isAdmin = isAdmin,
            dynamicCommands = dynamic,
            recentCommandIds = appPreferences.recentCommandIds,
        )
    }
}
