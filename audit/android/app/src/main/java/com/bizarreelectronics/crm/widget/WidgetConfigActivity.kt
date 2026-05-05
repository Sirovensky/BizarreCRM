package com.bizarreelectronics.crm.widget

import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.R
import com.bizarreelectronics.crm.ui.theme.BizarreCrmTheme

/**
 * §24.7 — Widget configuration activity launched by the launcher when the user
 * adds a Bizarre CRM home-screen widget.
 *
 * Android requires that a widget config activity:
 *   1. Have `android:exported="true"`.
 *   2. Read [AppWidgetManager.EXTRA_APPWIDGET_ID] from the launch intent.
 *   3. Set result to [RESULT_CANCELED] immediately (before user confirmation)
 *      and to [RESULT_OK] + the widget ID after successful configuration — this
 *      prevents the OS from adding the widget if the user backs out.
 *
 * Current configuration surface:
 * - Displays the widget ID for debugging.
 * - "Add widget" confirms placement; "Cancel" aborts.
 *
 * Future expansion (§24.7):
 * - Tenant picker (multi-tenant SaaS mode — when the user has access to
 *   multiple tenants, let them choose which tenant's data the widget shows).
 * - Time-range picker for revenue widget (today / this week / this month).
 * - Update frequency selector (30 min / 1 h / 2 h).
 *
 * These are left as TODO stubs to avoid scope creep — the config activity
 * skeleton satisfies the §24.7 "Config Activity on add" requirement.
 */
class WidgetConfigActivity : ComponentActivity() {

    private var appWidgetId = AppWidgetManager.INVALID_APPWIDGET_ID

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Set CANCELED immediately; changed to OK only on explicit user confirm.
        setResult(RESULT_CANCELED)

        appWidgetId = intent?.extras?.getInt(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID

        if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }

        setContent {
            BizarreCrmTheme {
                Surface(color = MaterialTheme.colorScheme.background) {
                    WidgetConfigScreen(
                        onConfirm = ::onConfirm,
                        onCancel = ::finish,
                    )
                }
            }
        }
    }

    private fun onConfirm() {
        // TODO(§24.7): persist tenant / time-range selection here before
        // writing the result.  For now the widget uses its defaults.
        val resultIntent = Intent().apply {
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
        }
        setResult(RESULT_OK, resultIntent)
        finish()
    }
}

// ── Compose UI ────────────────────────────────────────────────────────────

@Composable
private fun WidgetConfigScreen(
    onConfirm: () -> Unit,
    onCancel: () -> Unit,
) {
    Column(
        modifier = Modifier
            .padding(24.dp)
            .fillMaxWidth(),
    ) {
        Text(
            text = stringResource(R.string.widget_config_title),
            style = MaterialTheme.typography.headlineSmall,
        )

        Spacer(modifier = Modifier.height(8.dp))

        Text(
            text = stringResource(R.string.widget_config_subtitle),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        // TODO(§24.7): tenant picker + time-range picker composables go here.

        Spacer(modifier = Modifier.height(32.dp))

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            OutlinedButton(
                onClick = onCancel,
                modifier = Modifier.weight(1f),
            ) {
                Text(text = stringResource(R.string.action_cancel))
            }
            Button(
                onClick = onConfirm,
                modifier = Modifier.weight(1f),
            ) {
                Text(text = stringResource(R.string.widget_config_add))
            }
        }
    }
}
