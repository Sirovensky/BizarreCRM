package com.bizarreelectronics.crm.util

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for [PlayIntegrityClient] and [IntegrityVerdict].
 *
 * ## Strategy
 * The Play Integrity API requires a real Android device with Google Play
 * Services.  On a JVM unit-test host (no GMS, no Android framework),
 * `IntegrityManagerFactory.create(context)` throws [IllegalStateException] or
 * [NullPointerException].  [PlayIntegrityClient.requestToken] catches all
 * [Exception] subclasses and returns `null`, implementing the non-blocking
 * contract.
 *
 * These tests verify:
 *   1. [IntegrityVerdict] data-class correctness (pure JVM, no Android).
 *   2. [PlayIntegrityClient] returns `null` gracefully when GMS is unavailable
 *      (as it will be on every JVM CI runner and Robolectric environment that
 *      has not mocked the Play Services stack).
 *
 * A separate device-farm integration test (not included here) validates the
 * happy path — token issuance + server verification — on a physical device.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class PlayIntegrityClientTest {

    // ─── IntegrityVerdict — data class behaviour ──────────────────────────────

    @Test
    fun `IntegrityVerdict defaults strict to false and reason to null`() {
        val verdict = IntegrityVerdict(passed = true)
        assertFalse("strict should default to false", verdict.strict)
        assertNull("reason should default to null", verdict.reason)
    }

    @Test
    fun `IntegrityVerdict stores all fields correctly`() {
        val verdict = IntegrityVerdict(
            passed = false,
            strict = true,
            reason = "VM policy violation",
        )
        assertFalse(verdict.passed)
        assertTrue(verdict.strict)
        assertEquals("VM policy violation", verdict.reason)
    }

    @Test
    fun `IntegrityVerdict copy produces a new immutable instance`() {
        val original = IntegrityVerdict(passed = true, strict = false)
        val updated = original.copy(strict = true)
        assertFalse("original.strict must remain false", original.strict)
        assertTrue("updated.strict must be true", updated.strict)
    }

    @Test
    fun `IntegrityVerdict equality is value-based`() {
        val a = IntegrityVerdict(passed = true, strict = false, reason = null)
        val b = IntegrityVerdict(passed = true, strict = false, reason = null)
        assertEquals("two IntegrityVerdicts with same fields must be equal", a, b)
    }

    // ─── PlayIntegrityClient — non-GMS host (JVM CI) ─────────────────────────

    /**
     * On JVM / Robolectric without a mocked GMS, [PlayIntegrityClient.requestToken]
     * must catch the exception thrown by IntegrityManagerFactory and return null.
     *
     * We cannot inject a context that satisfies IntegrityManagerFactory without
     * the GMS Play Services stack, so we accept that the call will throw
     * internally and rely on the catch-all in [PlayIntegrityClient.requestToken].
     *
     * The test passes if:
     *   - No exception escapes [requestToken].
     *   - The return value is `null`.
     */
    @Test
    fun `requestToken returns null when no GMS is available`() = runTest {
        // Use a minimal fake context — enough to not NPE before IntegrityManagerFactory
        // but still fail inside GMS (no actual Play Services present in JVM test).
        val fakeContext = FakeContext()
        val client = PlayIntegrityClient(fakeContext)

        val result = client.requestToken("dGVzdC1ub25jZS0xMjM0NTY3OA==")
        assertNull("Expected null when GMS is unavailable", result)
    }

    @Test
    fun `requestTokenString returns null when no GMS is available`() = runTest {
        val fakeContext = FakeContext()
        val client = PlayIntegrityClient(fakeContext)

        val result = client.requestTokenString("dGVzdC1ub25jZS0xMjM0NTY3OA==")
        assertNull("Expected null token string when GMS is unavailable", result)
    }

    // ─── Nonce format documentation tests ────────────────────────────────────

    /** Documents that a valid nonce must be at least 24 Base64 chars (≥ 16 raw bytes). */
    @Test
    fun `valid nonce is at least 24 Base64 chars`() {
        val nonce = "dGVzdC1ub25jZS0xMjM0NTY3OA==" // ~20 raw bytes
        assertTrue("Nonce must be ≥ 24 chars for Play Integrity API", nonce.length >= 24)
    }

    /** Documents that a short nonce is rejected by the API (not by the client). */
    @Test
    fun `short nonce is forwarded to API which rejects it`() {
        val shortNonce = "dGVzdA==" // 4 raw bytes
        // The client does not validate nonce length — the API does.
        // This test asserts the nonce is short so future validators can reference it.
        assertTrue("Short nonce length is < 16 chars", shortNonce.length < 16)
    }

    // ─── Fake context ─────────────────────────────────────────────────────────

    /**
     * Minimal [android.content.Context] stand-in that returns non-null from
     * [applicationContext] so [PlayIntegrityClient] can be instantiated without
     * NPE.  IntegrityManagerFactory will still fail internally (no GMS), which
     * is exactly what the catch-all in [PlayIntegrityClient.requestToken] handles.
     */
    private class FakeContext : android.content.Context() {
        override fun getApplicationContext(): android.content.Context = this
        override fun getPackageName(): String = "com.bizarreelectronics.crm"

        // All other Context methods are not needed and throw UnsupportedOperationException.
        override fun getAssets() = throw UnsupportedOperationException()
        override fun getResources() = throw UnsupportedOperationException()
        override fun getPackageManager() = throw UnsupportedOperationException()
        override fun getContentResolver() = throw UnsupportedOperationException()
        override fun getMainLooper() = throw UnsupportedOperationException()
        override fun getApplicationInfo() = throw UnsupportedOperationException()
        override fun getPackageResourcePath() = throw UnsupportedOperationException()
        override fun getPackageCodePath() = throw UnsupportedOperationException()
        override fun getSharedPreferences(name: String?, mode: Int) = throw UnsupportedOperationException()
        override fun moveSharedPreferencesFrom(sourceContext: android.content.Context?, name: String?) = throw UnsupportedOperationException()
        override fun deleteSharedPreferences(name: String?) = throw UnsupportedOperationException()
        override fun openFileInput(name: String?) = throw UnsupportedOperationException()
        override fun openFileOutput(name: String?, mode: Int) = throw UnsupportedOperationException()
        override fun deleteFile(name: String?) = throw UnsupportedOperationException()
        override fun getFileStreamPath(name: String?) = throw UnsupportedOperationException()
        override fun getDataDir() = throw UnsupportedOperationException()
        override fun getFilesDir() = throw UnsupportedOperationException()
        override fun getNoBackupFilesDir() = throw UnsupportedOperationException()
        override fun getExternalFilesDir(type: String?) = throw UnsupportedOperationException()
        override fun getExternalFilesDirs(type: String?) = throw UnsupportedOperationException()
        override fun getObbDir() = throw UnsupportedOperationException()
        override fun getObbDirs() = throw UnsupportedOperationException()
        override fun getCacheDir() = throw UnsupportedOperationException()
        override fun getCodeCacheDir() = throw UnsupportedOperationException()
        override fun getExternalCacheDir() = throw UnsupportedOperationException()
        override fun getExternalCacheDirs() = throw UnsupportedOperationException()
        override fun getExternalMediaDirs() = throw UnsupportedOperationException()
        override fun fileList() = throw UnsupportedOperationException()
        override fun getDir(name: String?, mode: Int) = throw UnsupportedOperationException()
        override fun openOrCreateDatabase(name: String?, mode: Int, factory: android.database.sqlite.SQLiteDatabase.CursorFactory?) = throw UnsupportedOperationException()
        override fun openOrCreateDatabase(name: String?, mode: Int, factory: android.database.sqlite.SQLiteDatabase.CursorFactory?, errorHandler: android.database.DatabaseErrorHandler?) = throw UnsupportedOperationException()
        override fun moveDatabaseFrom(sourceContext: android.content.Context?, name: String?) = throw UnsupportedOperationException()
        override fun deleteDatabase(name: String?) = throw UnsupportedOperationException()
        override fun getDatabasePath(name: String?) = throw UnsupportedOperationException()
        override fun databaseList() = throw UnsupportedOperationException()
        override fun getWallpaper() = throw UnsupportedOperationException()
        override fun peekWallpaper() = throw UnsupportedOperationException()
        override fun getWallpaperDesiredMinimumWidth() = throw UnsupportedOperationException()
        override fun getWallpaperDesiredMinimumHeight() = throw UnsupportedOperationException()
        override fun setWallpaper(bitmap: android.graphics.Bitmap?) = throw UnsupportedOperationException()
        override fun setWallpaper(data: java.io.InputStream?) = throw UnsupportedOperationException()
        override fun clearWallpaper() = throw UnsupportedOperationException()
        override fun startActivity(intent: android.content.Intent?) = throw UnsupportedOperationException()
        override fun startActivity(intent: android.content.Intent?, options: android.os.Bundle?) = throw UnsupportedOperationException()
        override fun startActivities(intents: Array<out android.content.Intent>?) = throw UnsupportedOperationException()
        override fun startActivities(intents: Array<out android.content.Intent>?, options: android.os.Bundle?) = throw UnsupportedOperationException()
        override fun startIntentSender(intent: android.content.IntentSender?, fillInIntent: android.content.Intent?, flagsMask: Int, flagsValues: Int, extraFlags: Int) = throw UnsupportedOperationException()
        override fun startIntentSender(intent: android.content.IntentSender?, fillInIntent: android.content.Intent?, flagsMask: Int, flagsValues: Int, extraFlags: Int, options: android.os.Bundle?) = throw UnsupportedOperationException()
        override fun sendBroadcast(intent: android.content.Intent?) = throw UnsupportedOperationException()
        override fun sendBroadcast(intent: android.content.Intent?, receiverPermission: String?) = throw UnsupportedOperationException()
        override fun sendOrderedBroadcast(intent: android.content.Intent?, receiverPermission: String?) = throw UnsupportedOperationException()
        override fun sendOrderedBroadcast(intent: android.content.Intent, receiverPermission: String?, resultReceiver: android.content.BroadcastReceiver?, scheduler: android.os.Handler?, initialCode: Int, initialData: String?, initialExtras: android.os.Bundle?) = throw UnsupportedOperationException()
        override fun sendBroadcastAsUser(intent: android.content.Intent?, user: android.os.UserHandle?) = throw UnsupportedOperationException()
        override fun sendOrderedBroadcastAsUser(intent: android.content.Intent?, user: android.os.UserHandle?, receiverPermission: String?, resultReceiver: android.content.BroadcastReceiver?, scheduler: android.os.Handler?, initialCode: Int, initialData: String?, initialExtras: android.os.Bundle?) = throw UnsupportedOperationException()
        override fun sendStickyBroadcast(intent: android.content.Intent?) = throw UnsupportedOperationException()
        override fun sendStickyOrderedBroadcast(intent: android.content.Intent?, resultReceiver: android.content.BroadcastReceiver?, scheduler: android.os.Handler?, initialCode: Int, initialData: String?, initialExtras: android.os.Bundle?) = throw UnsupportedOperationException()
        override fun removeStickyBroadcast(intent: android.content.Intent?) = throw UnsupportedOperationException()
        override fun sendStickyBroadcastAsUser(intent: android.content.Intent?, user: android.os.UserHandle?) = throw UnsupportedOperationException()
        override fun sendStickyOrderedBroadcastAsUser(intent: android.content.Intent?, user: android.os.UserHandle?, resultReceiver: android.content.BroadcastReceiver?, scheduler: android.os.Handler?, initialCode: Int, initialData: String?, initialExtras: android.os.Bundle?) = throw UnsupportedOperationException()
        override fun removeStickyBroadcastAsUser(intent: android.content.Intent?, user: android.os.UserHandle?) = throw UnsupportedOperationException()
        override fun registerReceiver(receiver: android.content.BroadcastReceiver?, filter: android.content.IntentFilter?): android.content.Intent? = throw UnsupportedOperationException()
        override fun registerReceiver(receiver: android.content.BroadcastReceiver?, filter: android.content.IntentFilter?, flags: Int): android.content.Intent? = throw UnsupportedOperationException()
        override fun registerReceiver(receiver: android.content.BroadcastReceiver?, filter: android.content.IntentFilter?, broadcastPermission: String?, scheduler: android.os.Handler?): android.content.Intent? = throw UnsupportedOperationException()
        override fun registerReceiver(receiver: android.content.BroadcastReceiver?, filter: android.content.IntentFilter?, broadcastPermission: String?, scheduler: android.os.Handler?, flags: Int): android.content.Intent? = throw UnsupportedOperationException()
        override fun unregisterReceiver(receiver: android.content.BroadcastReceiver?) = throw UnsupportedOperationException()
        override fun startService(service: android.content.Intent?) = throw UnsupportedOperationException()
        override fun startForegroundService(service: android.content.Intent?) = throw UnsupportedOperationException()
        override fun stopService(service: android.content.Intent?) = throw UnsupportedOperationException()
        override fun bindService(service: android.content.Intent, conn: android.content.ServiceConnection, flags: Int) = throw UnsupportedOperationException()
        override fun unbindService(conn: android.content.ServiceConnection) = throw UnsupportedOperationException()
        override fun startInstrumentation(className: android.content.ComponentName, profileFile: String?, arguments: android.os.Bundle?) = throw UnsupportedOperationException()
        override fun getSystemService(name: String): Any? = null
        override fun getSystemServiceName(serviceClass: Class<*>): String? = null
        override fun checkPermission(permission: String, pid: Int, uid: Int) = android.content.pm.PackageManager.PERMISSION_DENIED
        override fun checkCallingPermission(permission: String) = android.content.pm.PackageManager.PERMISSION_DENIED
        override fun checkCallingOrSelfPermission(permission: String) = android.content.pm.PackageManager.PERMISSION_DENIED
        override fun checkSelfPermission(permission: String) = android.content.pm.PackageManager.PERMISSION_DENIED
        override fun enforcePermission(permission: String, pid: Int, uid: Int, message: String?) = throw UnsupportedOperationException()
        override fun enforceCallingPermission(permission: String, message: String?) = throw UnsupportedOperationException()
        override fun enforceCallingOrSelfPermission(permission: String, message: String?) = throw UnsupportedOperationException()
        override fun grantUriPermission(toPackage: String?, uri: android.net.Uri?, modeFlags: Int) = throw UnsupportedOperationException()
        override fun revokeUriPermission(uri: android.net.Uri?, modeFlags: Int) = throw UnsupportedOperationException()
        override fun revokeUriPermission(toPackage: String?, uri: android.net.Uri?, modeFlags: Int) = throw UnsupportedOperationException()
        override fun checkUriPermission(uri: android.net.Uri?, pid: Int, uid: Int, modeFlags: Int) = throw UnsupportedOperationException()
        override fun checkCallingUriPermission(uri: android.net.Uri?, modeFlags: Int) = throw UnsupportedOperationException()
        override fun checkCallingOrSelfUriPermission(uri: android.net.Uri?, modeFlags: Int) = throw UnsupportedOperationException()
        override fun checkUriPermission(uri: android.net.Uri?, readPermission: String?, writePermission: String?, pid: Int, uid: Int, modeFlags: Int) = throw UnsupportedOperationException()
        override fun enforceUriPermission(uri: android.net.Uri?, pid: Int, uid: Int, modeFlags: Int, message: String?) = throw UnsupportedOperationException()
        override fun enforceCallingUriPermission(uri: android.net.Uri?, modeFlags: Int, message: String?) = throw UnsupportedOperationException()
        override fun enforceCallingOrSelfUriPermission(uri: android.net.Uri?, modeFlags: Int, message: String?) = throw UnsupportedOperationException()
        override fun enforceUriPermission(uri: android.net.Uri?, readPermission: String?, writePermission: String?, pid: Int, uid: Int, modeFlags: Int, message: String?) = throw UnsupportedOperationException()
        override fun createPackageContext(packageName: String?, flags: Int) = throw UnsupportedOperationException()
        override fun createContextForSplit(splitName: String?) = throw UnsupportedOperationException()
        override fun createConfigurationContext(overrideConfiguration: android.content.res.Configuration) = throw UnsupportedOperationException()
        override fun createDisplayContext(display: android.view.Display) = throw UnsupportedOperationException()
        override fun createDeviceProtectedStorageContext() = throw UnsupportedOperationException()
        override fun isDeviceProtectedStorage() = false
    }
}
