package com.bizarreelectronics.crm.di

import com.bizarreelectronics.crm.ui.commandpalette.DynamicCommandProvider
import com.bizarreelectronics.crm.ui.commandpalette.SettingsDynamicCommandProvider
import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import dagger.multibindings.IntoSet
import dagger.multibindings.Multibinds

/**
 * Declares the [DynamicCommandProvider] multibinding set so Hilt can satisfy
 * the injection in [com.bizarreelectronics.crm.ui.commandpalette.CommandPaletteViewModel].
 *
 * §54.2 — [SettingsDynamicCommandProvider] is registered here so settings
 * destinations surface in the command palette by name. Future entity-search
 * providers (recent tickets, customers) should be added with @IntoSet.
 */
@Module
@InstallIn(SingletonComponent::class)
abstract class CommandPaletteModule {

    @Multibinds
    abstract fun dynamicCommandProviders(): Set<DynamicCommandProvider>

    /**
     * §54.2 — Contributes settings-destination commands (jump to any settings
     * sub-screen by name via the command palette).
     */
    @Binds
    @IntoSet
    abstract fun bindSettingsDynamicCommandProvider(
        impl: SettingsDynamicCommandProvider,
    ): DynamicCommandProvider
}
