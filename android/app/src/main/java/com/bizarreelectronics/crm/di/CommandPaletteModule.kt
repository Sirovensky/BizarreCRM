package com.bizarreelectronics.crm.di

import com.bizarreelectronics.crm.ui.commandpalette.DynamicCommandProvider
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import dagger.multibindings.Multibinds

/**
 * Declares the [DynamicCommandProvider] multibinding set so Hilt can satisfy
 * the injection in [com.bizarreelectronics.crm.ui.commandpalette.CommandPaletteViewModel].
 *
 * No concrete providers exist yet (see ActionPlan §54 for future entity
 * search providers). This empty-set declaration keeps the Hilt graph valid
 * until real providers are added with @IntoSet.
 */
@Module
@InstallIn(SingletonComponent::class)
abstract class CommandPaletteModule {

    @Multibinds
    abstract fun dynamicCommandProviders(): Set<DynamicCommandProvider>
}
