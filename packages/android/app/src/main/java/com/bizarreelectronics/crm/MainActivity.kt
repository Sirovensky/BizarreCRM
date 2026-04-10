package com.bizarreelectronics.crm

import android.os.Bundle
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
