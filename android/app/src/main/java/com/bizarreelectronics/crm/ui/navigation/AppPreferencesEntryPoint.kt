package com.bizarreelectronics.crm.ui.navigation

import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
import dagger.hilt.EntryPoint
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent

/**
 * §1.5 line 202 — Hilt EntryPoint so [AppNavGraph] can resolve
 * [AppPreferences] without requiring a ViewModel or a param change to every
 * call site. The bottom NavigationBar observes
 * [AppPreferences.tabNavOrderFlow] to apply the user's persisted tab order.
 *
 * Used via [dagger.hilt.android.EntryPointAccessors.fromApplication] inside
 * the AppNavGraph composable with a `runCatching` guard so previews and
 * non-Hilt test hosts that omit the Application-level component remain stable.
 */
@EntryPoint
@InstallIn(SingletonComponent::class)
interface AppPreferencesEntryPoint {
    fun appPreferences(): AppPreferences
}
