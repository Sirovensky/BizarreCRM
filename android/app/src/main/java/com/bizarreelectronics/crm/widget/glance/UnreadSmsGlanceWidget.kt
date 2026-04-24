package com.bizarreelectronics.crm.widget.glance

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.provideContent
import androidx.glance.appwidget.state.updateAppWidgetState
import androidx.glance.background
import androidx.glance.currentState
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.material3.ColorProviders
import androidx.glance.state.GlanceStateDefinition
import androidx.glance.state.PreferencesGlanceStateDefinition
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import com.bizarreelectronics.crm.MainActivity
import com.bizarreelectronics.crm.widget.glance.GlanceWidgetKeys.KEY_UNREAD_COUNT

/**
 * Glance home-screen widget that shows the count of unread SMS conversations.
 *
 * This widget is a **pure UI placeholder** — it reads an [Int] from a local
 * Glance [PreferencesGlanceStateDefinition] store and renders it.  No network
 * or repository calls are made inside the widget itself.
 *
 * ## State update entry point
 * Call [publishUnreadCount] (a top-level `suspend` helper at the bottom of
 * this file) whenever the SMS repository receives a new unread-count value
 * from the server.  Wiring that call into the repository is OUT OF SCOPE for
 * this scaffold — see the KDoc on [publishUnreadCount] for details.
 *
 * ## Click behaviour
 * Tapping the widget launches [MainActivity] with deep-link URI
 * `bizarrecrm://messages`, which the NavHost routes to the SMS inbox screen.
 *
 * ## Theme
 * Wraps content in [GlanceTheme] using [ColorProviders] from the M3 scheme
 * via `glance-material3`.  If token resolution fails on an older launcher the
 * Glance runtime falls back to its own default palette — no crash.
 */
class UnreadSmsGlanceWidget : GlanceAppWidget() {

    /** Preferences-backed state definition — no custom serialisation needed. */
    override val stateDefinition: GlanceStateDefinition<*> = PreferencesGlanceStateDefinition

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent {
            GlanceTheme {
                UnreadSmsBody(context = context)
            }
        }
    }
}

// ── Private composable ─────────────────────────────────────────────────────

/**
 * Root composable for the Unread SMS widget.
 *
 * Reads [KEY_UNREAD_COUNT] from the current Glance state preferences.
 * Renders "—" when the key is absent (widget freshly added, state not yet
 * populated by [publishUnreadCount]).
 */
@Composable
private fun UnreadSmsBody(context: Context) {
    val prefs = currentState<Preferences>()
    val unreadCount: Int? = prefs[intPreferencesKey(KEY_UNREAD_COUNT)]
    val countText = unreadCount?.toString() ?: "\u2014" // em dash

    val tapIntent = Intent(context, MainActivity::class.java).apply {
        data = Uri.parse("bizarrecrm://messages")
        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
    }

    Column(
        modifier = GlanceModifier
            .fillMaxSize()
            .background(GlanceTheme.colors.surface)
            .padding(horizontal = 12.dp, vertical = 8.dp)
            .clickable(actionStartActivity(tapIntent)),
        verticalAlignment = Alignment.Vertical.CenterVertically,
        horizontalAlignment = Alignment.Horizontal.CenterHorizontally,
    ) {
        Text(
            text = "Unread SMS",
            style = TextStyle(
                color = GlanceTheme.colors.onSurface,
                fontSize = 12.sp,
                fontWeight = FontWeight.Medium,
            ),
            modifier = GlanceModifier.fillMaxWidth(),
        )

        Spacer(modifier = GlanceModifier.height(4.dp))

        Text(
            text = countText,
            style = TextStyle(
                color = GlanceTheme.colors.primary,
                fontSize = 32.sp,
                fontWeight = FontWeight.Bold,
            ),
            modifier = GlanceModifier.fillMaxWidth(),
        )

        Spacer(modifier = GlanceModifier.height(4.dp))

        Text(
            text = "Tap to open inbox",
            style = TextStyle(
                color = GlanceTheme.colors.onSurfaceVariant,
                fontSize = 10.sp,
            ),
            modifier = GlanceModifier.fillMaxWidth(),
        )
    }
}

// ── Public state-update helper ─────────────────────────────────────────────

/**
 * Writes [count] into the Glance preferences store for every active instance
 * of [UnreadSmsGlanceWidget] and triggers a UI refresh.
 *
 * **Call site (OUT OF SCOPE for this scaffold):**
 * Wire this into the SMS sync path, e.g.:
 * ```kotlin
 * // Inside SmsRepository or a CoroutineWorker:
 * val unread = remoteDataSource.fetchUnreadCount()
 * publishUnreadCount(applicationContext, unread)
 * ```
 *
 * This function is `suspend` because [updateAppWidgetState] writes to a
 * DataStore under the hood.  Call it from a coroutine scope
 * (`viewModelScope`, `CoroutineWorker`, `lifecycleScope`).
 *
 * @param context Application context.
 * @param count   Number of unread SMS conversations; pass 0 to clear the badge.
 */
suspend fun publishUnreadCount(context: Context, count: Int) {
    val widget = UnreadSmsGlanceWidget()
    val glanceIds = GlanceAppWidgetManager(context)
        .getGlanceIds(UnreadSmsGlanceWidget::class.java)

    glanceIds.forEach { glanceId ->
        // Build a fresh MutablePreferences with the new count and hand it back
        // as the replacement state.  PreferencesGlanceStateDefinition merges
        // the result into DataStore; prior keys not present here are preserved.
        updateAppWidgetState(context, PreferencesGlanceStateDefinition, glanceId) {
            it.toMutablePreferences().also { m ->
                m[intPreferencesKey(KEY_UNREAD_COUNT)] = count
            }
        }
        widget.update(context, glanceId)
    }
}
