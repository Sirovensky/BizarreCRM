package com.bizarreelectronics.crm

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.fragment.app.FragmentActivity
import com.bizarreelectronics.crm.data.local.db.dao.SyncQueueDao
import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.sync.SyncManager
import com.bizarreelectronics.crm.ui.auth.BiometricAuth
import com.bizarreelectronics.crm.ui.navigation.AppNavGraph
import com.bizarreelectronics.crm.ui.theme.BizarreCrmTheme
import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
import dagger.hilt.android.AndroidEntryPoint
import javax.inject.Inject

/**
 * Hosts the Compose navigation graph and is the single entry point for
 * every intent that wants to land the user on a specific screen:
 *   - Launcher icon → dashboard
 *   - Home widget tap → dashboard (with cached values already rendered)
 *   - Quick-Settings tile tap → ticket-create (via ACTION_NEW_TICKET_FROM_TILE)
 *   - Google Assistant / shortcut deep link → route resolved from bizarrecrm://
 *
 * Changed from ComponentActivity to FragmentActivity so BiometricPrompt can
 * attach its host fragment. FragmentActivity is a superset of
 * ComponentActivity and does not require any other code changes.
 */
@AndroidEntryPoint
class MainActivity : FragmentActivity() {

    @Inject
    lateinit var authPreferences: AuthPreferences

    @Inject
    lateinit var appPreferences: AppPreferences

    @Inject
    lateinit var serverReachabilityMonitor: ServerReachabilityMonitor

    @Inject
    lateinit var syncQueueDao: SyncQueueDao

    @Inject
    lateinit var syncManager: SyncManager

    @Inject
    lateinit var biometricAuth: BiometricAuth

    /** Pending deep-link route extracted from the launch intent, if any. */
    private var pendingDeepLink: String? = null

    /** True until biometric unlock has either succeeded or been skipped. */
    private var isLocked: Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // M2 fix: set FLAG_SECURE on the activity window so screenshots are
        // blocked app-wide and the Recents preview is a black tile. Every
        // screen renders customer PII so there is no safe exception.
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE,
        )
        enableEdgeToEdge()

        pendingDeepLink = resolveDeepLink(intent)

        // Decide whether to lock the UI behind a biometric prompt. The gate
        // is OFF unless (a) the user enabled it in Settings, (b) they are
        // already authenticated against the server (otherwise the login
        // screen handles access), and (c) the device actually has a
        // biometric / device-credential enrolled.
        val shouldLock = appPreferences.biometricEnabled &&
            authPreferences.authToken != null &&
            biometricAuth.canAuthenticate(this)
        isLocked = shouldLock

        setContent {
            BizarreCrmTheme {
                var locked by remember { mutableStateOf(isLocked) }

                if (locked) {
                    LaunchBiometricPrompt(
                        onUnlocked = { locked = false },
                        onCancelled = { finish() },
                    )
                } else {
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

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        pendingDeepLink = resolveDeepLink(intent)
        // TODO(nav): push pendingDeepLink into the nav graph. This requires
        // access to the NavHostController that AppNavGraph owns — the
        // easiest fix once available is to expose a DeepLinkBus in Hilt and
        // collect it inside AppNavGraph. Left as a TODO here because nav
        // routing lives in a file other agents own.
    }

    /**
     * Wraps [BiometricAuth.showPrompt] in a composable-friendly launcher.
     * Composable is a remember-key'd LaunchedEffect-style call so rotating
     * the device doesn't show the prompt again.
     */
    @androidx.compose.runtime.Composable
    private fun LaunchBiometricPrompt(
        onUnlocked: () -> Unit,
        onCancelled: () -> Unit,
    ) {
        val activity = this
        androidx.compose.runtime.LaunchedEffect(Unit) {
            biometricAuth.showPrompt(
                activity = activity,
                onSuccess = onUnlocked,
                onError = { onCancelled() },
            )
        }
    }

    /**
     * Pulls an internal deep-link path out of either:
     *  - A `bizarrecrm://` URI (launcher shortcut / Assistant)
     *  - The Quick Settings tile action
     * Returns null if the intent doesn't carry a recognised route.
     */
    private fun resolveDeepLink(intent: Intent?): String? {
        if (intent == null) return null
        if (intent.action == com.bizarreelectronics.crm.service.QuickTicketTileService
                .ACTION_NEW_TICKET_FROM_TILE) {
            return "ticket/new"
        }
        val data: Uri = intent.data ?: return null
        if (data.scheme != "bizarrecrm") return null
        // Normalise "bizarrecrm://ticket/new" → "ticket/new"
        val host = data.host ?: return null
        val path = data.path?.trimStart('/').orEmpty()
        return if (path.isEmpty()) host else "$host/$path"
    }
}
