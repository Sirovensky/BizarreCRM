package com.bizarreelectronics.crm.testing

import dagger.Module
import dagger.Provides
import dagger.hilt.components.SingletonComponent
import dagger.hilt.testing.TestInstallIn
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestDispatcher
import javax.inject.Qualifier
import javax.inject.Singleton

/**
 * Qualifier for the IO dispatcher binding used by repositories and data sources.
 *
 * Mirror of any `@IoDispatcher` qualifier in production code. Rename to match
 * whatever qualifier name production [di/] modules use if they add one.
 */
@Qualifier
@Retention(AnnotationRetention.BINARY)
annotation class IoDispatcher

/**
 * Qualifier for the main / default dispatcher binding.
 */
@Qualifier
@Retention(AnnotationRetention.BINARY)
annotation class MainDispatcher

/**
 * TestDispatcherModule — replaces coroutine dispatcher bindings in unit tests.
 *
 * Provides a [StandardTestDispatcher] in place of [Dispatchers.IO] and
 * [Dispatchers.Main] so tests control coroutine execution deterministically
 * via `TestScope.advanceUntilIdle()` or `runTest { }` without real-thread
 * scheduling. The [TestDispatcher] itself is also provided as a singleton so
 * test classes can inject it directly for `advanceTimeBy` / assertion helpers.
 *
 * If production [di/] modules define `@IoDispatcher` / `@MainDispatcher`
 * qualifiers add the appropriate `replaces = [DispatcherModule::class]` entry
 * and mirror the `@Provides` signatures exactly.
 *
 * Plan ref: ActionPlan §1.6 line 223.
 */
@Module
@TestInstallIn(
    components = [SingletonComponent::class],
    replaces = [],  // Add replaces = [DispatcherModule::class] if/when that module is extracted.
)
object TestDispatcherModule {

    /**
     * Singleton [StandardTestDispatcher] shared across all injected dispatchers
     * so that `advanceUntilIdle()` on a [kotlinx.coroutines.test.TestScope]
     * drains work queued by any dispatcher injected from this module.
     */
    @Provides
    @Singleton
    fun provideTestDispatcher(): TestDispatcher = StandardTestDispatcher()

    /** IO dispatcher replacement — backed by the shared [TestDispatcher]. */
    @Provides
    @Singleton
    @IoDispatcher
    fun provideIoDispatcher(dispatcher: TestDispatcher): CoroutineDispatcher = dispatcher

    /** Main dispatcher replacement — backed by the shared [TestDispatcher]. */
    @Provides
    @Singleton
    @MainDispatcher
    fun provideMainDispatcher(dispatcher: TestDispatcher): CoroutineDispatcher = dispatcher
}
