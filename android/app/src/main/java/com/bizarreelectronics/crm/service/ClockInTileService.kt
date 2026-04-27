package com.bizarreelectronics.crm.service

import android.app.PendingIntent
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
        val isClockedIn = readClockedInPref()
        qsTile?.apply {
            label = "Clock In/Out"
            contentDescription = if (isClockedIn) "Currently clocked in — tap to open clock screen"
                                  else "Currently clocked out — tap to open clock screen"
            state = when (isClockedIn) {
                true  -> Tile.STATE_ACTIVE
                false -> Tile.STATE_INACTIVE
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

    /**
     * Reads the clock-in flag written by [publishClockState] into the Glance
     * DataStore's mirrored SharedPreferences file.
     *
     * Glance's [PreferencesGlanceStateDefinition] stores data in a DataStore
     * file per widget instance.  Because the tile cannot await a suspend
     * function in [onStartListening], we read the last-known value from a
     * lightweight SharedPreferences key that [publishClockState] also writes.
     *
     * TODO(§24.4): wire [PREFS_CLOCK_STATE] write into [publishClockState]
     * once the ViewModel call site is established.  For now the tile falls
     * back to INACTIVE (safe default — never shows a "clocked in" state that
     * is actually false).
     */
    private fun readClockedInPref(): Boolean {
        val prefs = applicationContext.getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
        return prefs.getBoolean(PREFS_CLOCK_STATE, false)
    }

    companion object {
        const val ACTION_CLOCK_IN_FROM_TILE =
            "com.bizarreelectronics.crm.action.CLOCK_IN_FROM_TILE"

        /** Shared prefs file + key mirrored from publishClockState for tile state reads. */
        const val PREFS_NAME = "clock_in_tile_prefs"
        const val PREFS_CLOCK_STATE = "is_clocked_in"
        private const val REQUEST_CODE = 101
    }
}
