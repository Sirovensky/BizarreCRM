package com.bizarreelectronics.crm.testing

/**
 * HiltTestModule — entry-point documentation for the Hilt test-double scaffold.
 *
 * This package provides `@TestInstallIn` replacements for production Hilt modules
 * so that unit tests run without real I/O (no SQLCipher DB, no live network,
 * no Android Keystore). Each replacement module is self-contained:
 *
 *  - [TestDatabaseModule]   — replaces [com.bizarreelectronics.crm.di.DatabaseModule]
 *                             with an in-memory Room database (no SQLCipher).
 *  - [TestApiModule]        — replaces [com.bizarreelectronics.crm.di.NetworkModule]
 *                             with a no-op Retrofit stub backed by [TestRetrofitService].
 *  - [TestDataStoreModule]  — replaces the EncryptedSharedPreferences binding with
 *                             an in-memory [android.content.SharedPreferences] substitute.
 *  - [TestDispatcherModule] — replaces [kotlinx.coroutines.Dispatchers.IO] with a
 *                             [kotlinx.coroutines.test.TestCoroutineDispatcher] for
 *                             deterministic coroutine control.
 *
 * Usage: simply depend on these source files in `src/test/`. Hilt's annotation
 * processor picks up `@TestInstallIn` automatically for `@HiltAndroidTest` classes.
 *
 * Plan ref: ActionPlan §1.6 line 223.
 */
// This file is intentionally declaration-only; it exists as a package-level KDoc.
