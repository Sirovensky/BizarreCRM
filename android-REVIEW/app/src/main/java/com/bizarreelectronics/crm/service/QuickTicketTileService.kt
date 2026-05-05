package com.bizarreelectronics.crm.service

import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import androidx.annotation.RequiresApi
import com.bizarreelectronics.crm.MainActivity

/**
 * Quick Settings tile (Android 7+) that lets technicians start a new
 * ticket directly from the pull-down notification shade. When tapped, the
 * tile launches MainActivity with an intent extra that tells the app to
 * navigate to the ticket-create route.
 *
 * Registered in AndroidManifest.xml with BIND_QUICK_SETTINGS_TILE
 * permission and the action android.service.quicksettings.action.QS_TILE.
 */
class QuickTicketTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        qsTile?.apply {
            state = Tile.STATE_ACTIVE
            label = "New Ticket"
            contentDescription = "Create a new repair ticket"
            updateTile()
        }
    }

    override fun onClick() {
        super.onClick()
        val launch = Intent(this, MainActivity::class.java).apply {
            action = ACTION_NEW_TICKET_FROM_TILE
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }

        // Android 14+ requires PendingIntent wrapping for TileService.
        // Below that we can use startActivityAndCollapse(Intent) directly.
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
            0,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        startActivityAndCollapse(pending)
    }

    companion object {
        const val ACTION_NEW_TICKET_FROM_TILE =
            "com.bizarreelectronics.crm.action.NEW_TICKET_FROM_TILE"
    }
}
