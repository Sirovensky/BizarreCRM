package com.bizarreelectronics.crm.widget.glance

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
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
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.state.GlanceStateDefinition
import androidx.glance.state.PreferencesGlanceStateDefinition
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import com.bizarreelectronics.crm.MainActivity
import com.bizarreelectronics.crm.widget.glance.ClockInWidgetKeys.KEY_CLOCKED_IN
import com.bizarreelectronics.crm.widget.glance.ClockInWidgetKeys.KEY_EMPLOYEE_NAME

/**
 * §24.1 — Glance home-screen widget for clock-in / clock-out toggle.
 *
 * Reads [KEY_CLOCKED_IN] (Boolean) and [KEY_EMPLOYEE_NAME] (String) from a
 * [PreferencesGlanceStateDefinition] DataStore.  State is pushed by
 * [publishClockState] (called from the clock-in/out ViewModel after a
 * successful toggle).
 *
 * Tapping the widget launches [MainActivity] with deep-link
 * `bizarrecrm://clockinout` so the user can confirm/cancel from the full
 * ClockInOutScreen — the widget itself does NOT call the API directly to
 * avoid unintended clock actions from a home-screen mis-tap.
 *
 * Theme tokens come from [GlanceTheme] (no hardcoded colors).
 */
class ClockInGlanceWidget : GlanceAppWidget() {

    override val stateDefinition: GlanceStateDefinition<*> = PreferencesGlanceStateDefinition

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent {
            GlanceTheme {
                ClockInWidgetBody(context = context)
            }
        }
    }
}

// ── Private composable ─────────────────────────────────────────────────────

@Composable
private fun ClockInWidgetBody(context: Context) {
    val prefs = currentState<Preferences>()
    val isClockedIn: Boolean = prefs[booleanPreferencesKey(KEY_CLOCKED_IN)] ?: false
    val employeeName: String = prefs[stringPreferencesKey(KEY_EMPLOYEE_NAME)] ?: ""

    val tapIntent = Intent(context, MainActivity::class.java).apply {
        data = Uri.parse("bizarrecrm://clockinout")
        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
    }

    // Status indicator label changes with clock state.
    val statusLabel = if (isClockedIn) "Clocked in" else "Clocked out"
    val actionHint = "Tap to open clock screen"

    Column(
        modifier = GlanceModifier
            .fillMaxSize()
            .background(GlanceTheme.colors.surface)
            .padding(horizontal = 12.dp, vertical = 8.dp)
            .clickable(actionStartActivity(tapIntent)),
        verticalAlignment = Alignment.Vertical.CenterVertically,
    ) {
        Row(
            verticalAlignment = Alignment.Vertical.CenterVertically,
        ) {
            // Status indicator dot — primary when clocked in, surfaceVariant otherwise.
            androidx.glance.layout.Box(
                modifier = GlanceModifier
                    .size(10.dp)
                    .background(
                        if (isClockedIn) GlanceTheme.colors.primary
                        else GlanceTheme.colors.surfaceVariant,
                    ),
            ) {}
            Spacer(modifier = GlanceModifier.width(6.dp))
            Text(
                text = statusLabel,
                style = TextStyle(
                    color = if (isClockedIn) GlanceTheme.colors.primary
                            else GlanceTheme.colors.onSurface,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Bold,
                ),
            )
        }

        if (employeeName.isNotBlank()) {
            Spacer(modifier = GlanceModifier.height(2.dp))
            Text(
                text = employeeName,
                style = TextStyle(
                    color = GlanceTheme.colors.onSurfaceVariant,
                    fontSize = 11.sp,
                ),
                modifier = GlanceModifier.fillMaxWidth(),
            )
        }

        Spacer(modifier = GlanceModifier.height(4.dp))

        Text(
            text = actionHint,
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
 * Writes the latest clock state into the Glance DataStore for every active
 * [ClockInGlanceWidget] instance and triggers a UI refresh.
 *
 * Call this from the clock-in/out ViewModel after a successful API toggle:
 * ```kotlin
 * publishClockState(applicationContext, isClockedIn = true, employeeName = "Alex")
 * ```
 *
 * @param context      Application context.
 * @param isClockedIn  True when the employee just clocked in; false when clocked out.
 * @param employeeName Display name shown below the status label; pass empty to hide.
 */
suspend fun publishClockState(context: Context, isClockedIn: Boolean, employeeName: String = "") {
    val widget = ClockInGlanceWidget()
    val glanceIds = GlanceAppWidgetManager(context)
        .getGlanceIds(ClockInGlanceWidget::class.java)

    glanceIds.forEach { glanceId ->
        updateAppWidgetState(context, PreferencesGlanceStateDefinition, glanceId) {
            it.toMutablePreferences().also { m ->
                m[booleanPreferencesKey(KEY_CLOCKED_IN)] = isClockedIn
                m[stringPreferencesKey(KEY_EMPLOYEE_NAME)] = employeeName
            }
        }
        widget.update(context, glanceId)
    }
}

// ── Key constants ──────────────────────────────────────────────────────────

object ClockInWidgetKeys {
    const val KEY_CLOCKED_IN = "clock_in_state"
    const val KEY_EMPLOYEE_NAME = "clock_in_employee_name"
}
