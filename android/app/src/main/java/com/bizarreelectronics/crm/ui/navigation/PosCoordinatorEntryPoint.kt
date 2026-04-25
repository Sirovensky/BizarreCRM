package com.bizarreelectronics.crm.ui.navigation

import com.bizarreelectronics.crm.ui.screens.pos.PosCoordinator
import dagger.hilt.EntryPoint
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent

/**
 * Hilt EntryPoint that lets non-injected callers (e.g. AppNavGraph composable
 * code that needs to resolve the singleton from inside an `onClick` lambda)
 * grab the [PosCoordinator]. Used by the POS-tab re-tap reset dialog so the
 * cashier can read pending cart state and call resetSession() without
 * routing through a ViewModel.
 */
@EntryPoint
@InstallIn(SingletonComponent::class)
interface PosCoordinatorEntryPoint {
    fun posCoordinator(): PosCoordinator
}
