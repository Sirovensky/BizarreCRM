package com.bizarreelectronics.crm.ui.components

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.BuildConfig

/**
 * L2522 — Force-upgrade full-screen blocker.
 *
 * Renders a full-screen overlay when the server reports a minimum required
 * version code that is higher than [BuildConfig.VERSION_CODE].  The user
 * cannot dismiss the screen — they must update the app via the Play Store.
 *
 * ## Mount point
 * Call this from the root scaffold, wrapping the normal app content:
 * ```kotlin
 * ForceUpgradeBlocker(serverMinVersion = serverMinVersion) {
 *     // normal app content
 * }
 * ```
 *
 * ## Server contract
 * The server returns `min_version` (Int) on `GET /auth/me` and `GET /tenants/me`.
 * The Android client reads [AuthPreferences.serverMinVersion] which is populated
 * from those responses.  A missing field (null) means no minimum is enforced.
 *
 * ## Play Store fallback
 * On devices without Play Store (de-Googled ROMs, enterprise) the market://
 * intent falls back to a web browser opening the Play Store URL.
 *
 * @param serverMinVersion Minimum version code required by the server.  `null`
 *   means no restriction; content is rendered normally.
 * @param content          The composable content to display when no upgrade is
 *   required.
 */
@Composable
fun ForceUpgradeBlocker(
    serverMinVersion: Int?,
    content: @Composable () -> Unit,
) {
    val currentVersion = BuildConfig.VERSION_CODE
    val upgradeRequired = serverMinVersion != null && currentVersion < serverMinVersion

    if (upgradeRequired) {
        ForceUpgradeScreen()
    } else {
        content()
    }
}

/**
 * Full-screen blocking UI shown when a force-upgrade is required.
 *
 * Displays the app name, a "Update required" heading, a short explanation,
 * and a button that opens the Play Store listing.  There is no way to dismiss
 * this screen — it replaces the entire content hierarchy.
 */
@Composable
private fun ForceUpgradeScreen() {
    val context = LocalContext.current
    val packageName = context.packageName

    Surface(
        modifier = Modifier.fillMaxSize(),
        color = MaterialTheme.colorScheme.background,
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(32.dp),
            contentAlignment = Alignment.Center,
        ) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                Text(
                    text = "Update Required",
                    style = MaterialTheme.typography.headlineMedium,
                    textAlign = TextAlign.Center,
                )
                Spacer(modifier = Modifier.height(16.dp))
                Text(
                    text = "A newer version of Bizarre Electronics CRM is required to " +
                        "continue.  Please update the app from the Play Store.",
                    style = MaterialTheme.typography.bodyLarge,
                    textAlign = TextAlign.Center,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(modifier = Modifier.height(32.dp))
                Button(
                    onClick = {
                        val intent = Intent(
                            Intent.ACTION_VIEW,
                            Uri.parse("market://details?id=$packageName"),
                        ).also { it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }

                        // Fallback to web URL if Play Store app is not installed
                        val fallbackIntent = Intent(
                            Intent.ACTION_VIEW,
                            Uri.parse("https://play.google.com/store/apps/details?id=$packageName"),
                        ).also { it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }

                        try {
                            context.startActivity(intent)
                        } catch (_: android.content.ActivityNotFoundException) {
                            context.startActivity(fallbackIntent)
                        }
                    },
                ) {
                    Text("Open Play Store")
                }
                Spacer(modifier = Modifier.height(16.dp))
                Text(
                    text = "Current version: ${BuildConfig.VERSION_NAME}",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.outline,
                )
            }
        }
    }
}
