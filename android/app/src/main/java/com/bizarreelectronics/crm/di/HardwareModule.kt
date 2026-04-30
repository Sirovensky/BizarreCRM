package com.bizarreelectronics.crm.di

import com.bizarreelectronics.crm.ui.screens.pos.CashDrawerControllerStub
import com.bizarreelectronics.crm.util.CashDrawerController
import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

/**
 * Hilt module for hardware singletons.
 *
 * §17.4/17.5 — [CashDrawerController] bound to [CashDrawerControllerStub].
 *
 * §17.7 — [WeightScaleService] and [HardwareRepository] are
 * `@Singleton @Inject constructor` so Hilt builds them directly; no binding
 * needed here (no interface to bind against).
 *
 * §17.8 — [NfcRepository] is `@Singleton @Inject constructor`; no interface binding.
 *
 * §17.10 — [HidBarcodeScanner] is `@Singleton @Inject constructor`; no interface binding.
 *
 * §17.12 — [PrinterManager] is `@Singleton @Inject constructor`; no interface binding.
 */
@Module
@InstallIn(SingletonComponent::class)
abstract class HardwareModule {

    @Binds
    @Singleton
    abstract fun bindCashDrawerController(impl: CashDrawerController): CashDrawerControllerStub
}
