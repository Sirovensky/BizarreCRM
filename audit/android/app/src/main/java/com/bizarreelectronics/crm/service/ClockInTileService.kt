package com.bizarreelectronics.crm.service

import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import androidx.annotation.RequiresApi
import com.bizarreelectronics.crm.MainActivity

/**
 * §24.4 — Quick Settings tile for clocking in or out of a shift.
 *
 * The tile reflects the employee's current shift state: [Tile.STATE_ACTIVE]
 * (green) when clocked in, [Tile.STATE_INACTIVE] when clocked out, and
 * [Tile.STATE_UNAVAILABLE] when the shift state is unknown (e.g. not yet
 * loaded, or user is not logged in).
 *
 * ## State persistence
 * [TileService] is a bound service that the OS may start/stop at any time.
 * To read the latest clock state we pull from the same shared preferences
 * used by [ClockInGlanceWidget] (key [ClockInWidgetKeys.KEY_CLOCKED_IN]).
 * This avoids a synchronous network call inside [onStartListening].
 *
 * ## Tap behaviour
 * Tapping opens [MainActivity] with deep-link `bizarrecrm://clockinout`.
 * The QS tile does NOT directly call the clock-in API to avoid accidental
 * toggles from a swipe-down mis-tap.  The ClockInOutScreen handles the
 * full PIN-confirm + API call flow.
 *
 * ## Manifest
 * Declared in AndroidManifest.xml with
 * `android:permission="android.permission.BIND_QUICK_SETTINGS_TILE"`.
 */
class ClockInTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        val prefs = applicationContext.getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
        val isLoggedIn = prefs.getBoolean(PREFS_LOGGED_IN, false)
        val isClockedIn = prefs.getBoolean(PREFS_CLOCK_STATE, false)
        qsTile?.apply {
            label = "Clock In/Out"
            if (!isLoggedIn) {
                contentDescription = "Not signed in — open app to log in"
                state = Tile.STATE_UNAVAILABLE
            } else {
                contentDescription = if (isClockedIn) "Currently clocked in — tap to open clock screen"
                                     else "Currently clocked out — tap to open clock screen"
                state = if (isClockedIn) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
            }
            updateTile()
        }
    }

    override fun onStopListening() {
        super.onStopListening()
    }

    override fun onClick() {
        super.onClick()
        val launch = Intent(this, MainActivity::class.java).apply {
            action = ACTION_CLOCK_IN_FROM_TILE
            data = android.net.Uri.parse("bizarrecrm://clockinout")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            collapseAndLaunch(launch)
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(launch)
        }
    }

    @RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
    private fun collapseAndLaunch(launch: Intent) {
        val pending = PendingIntent.getActivity(
            this,
            REQUEST_CODE,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        startActivityAndCollapse(pending)
    }

    companion object {
        const val ACTION_CLOCK_IN_FROM_TILE =
            "com.bizarreelectronics.crm.action.CLOCK_IN_FROM_TILE"

        /** Shared prefs file and keys read by [onStartListening]. */
        const val PREFS_NAME = "clock_in_tile_prefs"
        const val PREFS_CLOCK_STATE = "is_clocked_in"

        /**
         * Whether the user is currently logged in; determines [Tile.STATE_UNAVAILABLE]
         * vs the normal active/inactive states.
         */
        const val PREFS_LOGGED_IN = "is_logged_in"

        private const val REQUEST_CODE = 101

        /**
         * §14.10 — Persists the employee's current clock state to the
         * SharedPreferences file read by [onStartListening] and notifies the
         * OS to call [onStartListening] again so the tile UI refreshes
         * immediately without requiring the shade to be re-opened.
         *
         * Call this after every successful clock-in or clock-out:
         * ```kotlin
         * ClockInTileService.persistClockState(appContext, isClockedIn = true)
         * ```
         *
         * @param context       Application context (not Activity context).
         * @param isClockedIn   True when the employee just clocked in; false on clock-out.
         * @param isLoggedIn    Whether a valid session exists; drives [Tile.STATE_UNAVAILABLE].
         *                      Defaults to true because this is only called from authenticated paths.
         */
        fun persistClockState(
            context: Context,
            isClockedIn: Boolean,
            isLoggedIn: Boolean = true,
        ) {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(PREFS_CLOCK_STATE, isClockedIn)
                .putBoolean(PREFS_LOGGED_IN, isLoggedIn)
                .apply()

            // Ask the OS to call onStartListening() on the next bound tile instance.
            // Safe to call even when no tile is added to the shade — a no-op then.
            TileService.requestListeningState(
                context,
                ComponentName(context, ClockInTileService::class.java),
            )
        }
    }
}
