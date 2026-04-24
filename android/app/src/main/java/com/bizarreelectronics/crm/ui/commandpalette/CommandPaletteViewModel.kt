package com.bizarreelectronics.crm.ui.commandpalette

import androidx.lifecycle.ViewModel
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import javax.inject.Inject

/**
 * §54 — ViewModel for the command palette overlay.
 *
 * Merges [CommandRegistry.staticCommands] with any [DynamicCommandProvider]
 * implementations injected by Hilt. Filters by the live [query] state and
 * gates admin-only commands against the current user role from [AuthPreferences].
 */
@HiltViewModel
class CommandPaletteViewModel @Inject constructor(
    private val authPreferences: AuthPreferences,
    private val dynamicProviders: @JvmSuppressWildcards Set<DynamicCommandProvider>,
) : ViewModel() {

    private val _query = MutableStateFlow("")
    val query: StateFlow<String> = _query.asStateFlow()

    private val _results = MutableStateFlow<List<Command>>(emptyList())
    val results: StateFlow<List<Command>> = _results.asStateFlow()

    init {
        // Build initial unfiltered list on construction.
        refresh("")
    }

    fun onQueryChange(newQuery: String) {
        _query.value = newQuery
        refresh(newQuery)
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
        )
    }
}
