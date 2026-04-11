package com.bizarreelectronics.crm

import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.bizarreelectronics.crm.data.local.db.dao.SyncQueueDao
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.sync.SyncManager
import com.bizarreelectronics.crm.ui.navigation.AppNavGraph
import com.bizarreelectronics.crm.ui.theme.BizarreCrmTheme
import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
import dagger.hilt.android.AndroidEntryPoint
import javax.inject.Inject

@AndroidEntryPoint
class MainActivity : ComponentActivity() {

    @Inject
    lateinit var authPreferences: AuthPreferences

    @Inject
    lateinit var serverReachabilityMonitor: ServerReachabilityMonitor

    @Inject
    lateinit var syncQueueDao: SyncQueueDao

    @Inject
    lateinit var syncManager: SyncManager

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // M2 fix: set FLAG_SECURE on the activity window so that:
        //   - screenshots are blocked app-wide (no accidental customer PII
        //     leaking out via the Recents screen grid, screen recording, or
        //     Google Assistant scene understanding)
        //   - the contents do not show up in the system's app-switcher
        //     preview (Recents shows a black tile for this app)
        //
        // Every screen in this CRM renders customer PII, payment totals, SMS
        // bodies, or tax IDs, so there is no screen where screenshots are
        // actually safe. Setting FLAG_SECURE once at the activity level is the
        // correct blast radius here — screens do not need to opt in/out.
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE,
        )
        enableEdgeToEdge()
        setContent {
            BizarreCrmTheme {
                AppNavGraph(
                    authPreferences = authPreferences,
                    serverReachabilityMonitor = serverReachabilityMonitor,
                    syncQueueDao = syncQueueDao,
                    syncManager = syncManager,
                )
            }
        }
    }
}
