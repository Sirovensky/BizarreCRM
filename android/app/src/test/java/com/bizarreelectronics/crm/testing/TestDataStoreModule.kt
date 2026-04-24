package com.bizarreelectronics.crm.testing

import android.content.Context
import android.content.SharedPreferences
import dagger.Module
import dagger.Provides
import dagger.hilt.components.SingletonComponent
import dagger.hilt.testing.TestInstallIn
import javax.inject.Qualifier
import javax.inject.Singleton

/**
 * Qualifier for the in-memory [SharedPreferences] provided in tests.
 *
 * Inject with `@TestSharedPrefs` wherever you need a SharedPreferences stand-in
 * that does not touch EncryptedSharedPreferences / Android Keystore.
 */
@Qualifier
@Retention(AnnotationRetention.BINARY)
annotation class TestSharedPrefs

/**
 * TestDataStoreModule — provides in-memory SharedPreferences in unit tests.
 *
 * Production code that reads `AuthPreferences` or `PinPreferences` uses
 * `EncryptedSharedPreferences`, which requires Android Keystore hardware and
 * is unavailable in JVM unit tests. This module does NOT replace those
 * concrete classes (they are `@Inject constructor`-bound, not module-provided),
 * but it exposes a raw `SharedPreferences` binding tagged [TestSharedPrefs] so
 * test helpers and custom fakes can obtain a lightweight in-memory store without
 * instantiating the crypto stack.
 *
 * If a future refactor extracts a `SharedPreferences @Provides` from a dedicated
 * `PrefsModule`, add `replaces = [PrefsModule::class]` to this annotation.
 *
 * Plan ref: ActionPlan §1.6 line 223.
 */
@Module
@TestInstallIn(
    components = [SingletonComponent::class],
    replaces = [],   // No production @Module to replace — prefs use @Inject constructor.
)
object TestDataStoreModule {

    /**
     * Returns an in-memory [SharedPreferences] via [Context.getSharedPreferences]
     * in `MODE_PRIVATE`. In Robolectric / test contexts this is backed by an
     * in-memory map and discarded after the test process exits.
     */
    @Provides
    @Singleton
    @TestSharedPrefs
    fun provideTestSharedPreferences(context: Context): SharedPreferences =
        context.getSharedPreferences("test_prefs_in_memory", Context.MODE_PRIVATE)
}
