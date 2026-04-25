package com.bizarreelectronics.crm.di

import com.bizarreelectronics.crm.ui.screens.pos.CashDrawerControllerStub
import com.bizarreelectronics.crm.util.CashDrawerController
import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

/**
 * Binds the [CashDrawerController] singleton to the [CashDrawerControllerStub]
 * interface so ViewModels (e.g. [PosReceiptViewModel]) can depend on the
 * abstraction instead of the concrete hardware class.
 *
 * [CashDrawerController] is already `@Singleton @Inject constructor(…)` so Hilt
 * knows how to build it; this module just exposes the binding under the interface
 * type.
 */
@Module
@InstallIn(SingletonComponent::class)
abstract class HardwareModule {

    @Binds
    @Singleton
    abstract fun bindCashDrawerController(impl: CashDrawerController): CashDrawerControllerStub
}
