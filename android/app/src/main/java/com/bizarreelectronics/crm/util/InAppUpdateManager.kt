package com.bizarreelectronics.crm.util

import android.app.Activity
import android.content.Context
import com.bizarreelectronics.crm.BuildConfig
import com.google.android.play.core.appupdate.AppUpdateInfo
import com.google.android.play.core.appupdate.AppUpdateManager
import com.google.android.play.core.appupdate.AppUpdateManagerFactory
import com.google.android.play.core.appupdate.AppUpdateOptions
import com.google.android.play.core.install.model.AppUpdateType
import com.google.android.play.core.install.model.UpdateAvailability
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.suspendCancellableCoroutine
import timber.log.Timber
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.coroutines.resume

/**
 * §33.9 — Play In-App Update stub.
 *
 * Decision matrix:
 *   - Server returns minVersionCode > current BUILD → IMMEDIATE update forced.
 *   - Play Store has a flexible update available → FLEXIBLE update offered.
 *   - No GMS / non-Play install → silently skipped (non-blocking).
 *
 * Caller (typically MainActivity or a top-level ViewModel) should invoke
 * [checkAndStartUpdate] from onResume. For FLEXIBLE updates also call
 * [completeFlexibleUpdate] from a "Restart to apply update" snackbar action.
 *
 * NOTE: This is a wired stub — the AppUpdateManager is real and will trigger
 * the Play overlay when the app is installed via the Play Store. On AOSP /
 * sideloaded builds the [checkAndStartUpdate] call returns silently because
 * [AppUpdateManagerFactory.create] wraps a no-op on non-GMS devices.
 */
@Singleton
class InAppUpdateManager @Inject constructor(
    @ApplicationContext private val context: Context,
) {
    companion object {
        // §33.9: request code passed to the Play in-app update flow.
        // Activity.onActivityResult sees this code when the update flow resolves.
        const val UPDATE_REQUEST_CODE = 7301
    }

    private val appUpdateManager: AppUpdateManager by lazy {
        AppUpdateManagerFactory.create(context)
    }

    /**
     * Call from Activity.onResume.
     *
     * 1. Asks the Play Store for update info (non-blocking task).
     * 2. Compares [AppUpdateInfo.availableVersionCode] against
     *    [BuildConfig.FORCE_UPDATE_FLOOR_VERSION].  If available code is
     *    strictly greater, launches an IMMEDIATE update (blocks UI until done).
     * 3. Otherwise, if any flexible update is available, launches a FLEXIBLE
     *    update overlay (user can dismiss and update in background).
     *
     * All failures are caught and logged; the app continues normally so a
     * transient Play Services outage never blocks the user.
     */
    fun checkAndStartUpdate(activity: Activity) {
        val updateInfoTask = appUpdateManager.appUpdateInfo
        updateInfoTask.addOnSuccessListener { info ->
            try {
                when {
                    shouldForceImmediateUpdate(info) -> {
                        Timber.w(
                            "InAppUpdate: force-immediate triggered — " +
                            "available=${info.availableVersionCode()} " +
                            "floor=${BuildConfig.FORCE_UPDATE_FLOOR_VERSION}",
                        )
                        appUpdateManager.startUpdateFlow(
                            info,
                            activity,
                            AppUpdateOptions.newBuilder(AppUpdateType.IMMEDIATE).build(),
                        )
                    }
                    shouldOfferFlexibleUpdate(info) -> {
                        Timber.i(
                            "InAppUpdate: flexible update available — " +
                            "available=${info.availableVersionCode()}",
                        )
                        appUpdateManager.startUpdateFlow(
                            info,
                            activity,
                            AppUpdateOptions.newBuilder(AppUpdateType.FLEXIBLE).build(),
                        )
                    }
                    else -> Timber.d("InAppUpdate: no update action needed")
                }
            } catch (e: Exception) {
                // Non-Play / AOSP builds throw here — swallow gracefully.
                Timber.d(e, "InAppUpdate: startUpdateFlow skipped (non-Play build?)")
            }
        }
        updateInfoTask.addOnFailureListener { e ->
            Timber.d(e, "InAppUpdate: failed to fetch update info — non-blocking")
        }
    }

    /**
     * Call after a FLEXIBLE update download completes (typically from a
     * "Restart now" snackbar shown by the caller when
     * [com.google.android.play.core.install.InstallState] reports
     * [com.google.android.play.core.install.model.InstallStatus.DOWNLOADED]).
     */
    fun completeFlexibleUpdate() {
        try {
            appUpdateManager.completeUpdate()
        } catch (e: Exception) {
            Timber.d(e, "InAppUpdate: completeUpdate skipped (non-Play build?)")
        }
    }

    // ── private helpers ──────────────────────────────────────────────────────

    /**
     * Force IMMEDIATE when the server-configured floor is non-zero AND the
     * available Play Store version exceeds that floor. This covers the
     * kill-switch case: ship a new build, set FORCE_UPDATE_FLOOR_VERSION to
     * its versionCode in the next release, and all older installs are blocked.
     */
    private fun shouldForceImmediateUpdate(info: AppUpdateInfo): Boolean =
        BuildConfig.FORCE_UPDATE_FLOOR_VERSION > 0 &&
        info.updateAvailability() == UpdateAvailability.UPDATE_AVAILABLE &&
        info.availableVersionCode() > BuildConfig.FORCE_UPDATE_FLOOR_VERSION &&
        info.isUpdateTypeAllowed(AppUpdateType.IMMEDIATE)

    /**
     * Offer FLEXIBLE when an update is available and the force floor is not
     * triggered. Avoids nagging for every patch — Play only surfaces this when
     * the update has been available for a minimum staleness period configured
     * in the Play Console (default 7 days).
     */
    private fun shouldOfferFlexibleUpdate(info: AppUpdateInfo): Boolean =
        info.updateAvailability() == UpdateAvailability.UPDATE_AVAILABLE &&
        info.isUpdateTypeAllowed(AppUpdateType.FLEXIBLE)
}
