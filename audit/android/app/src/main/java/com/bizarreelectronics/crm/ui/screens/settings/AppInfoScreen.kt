package com.bizarreelectronics.crm.ui.screens.settings

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.BugReport
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.material3.LocalContentColor
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Gavel
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.BuildConfig
import kotlinx.coroutines.launch

/**
 * §19.14 — App Info / About screen.
 *
 * Provides:
 *   - Open-source licenses (via OssLicensesMenuActivity from play-services-oss-licenses)
 *   - Privacy policy (external browser link)
 *   - Terms of service (external browser link)
 *   - Rate the app on the Play Store (in-app review flow stub; falls back to store link)
 *
 * This is distinct from [AboutScreen] (which shows the diagnostic copy-bundle).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AppInfoScreen(
    onBack: () -> Unit,
    /** Navigate to the diagnostic copy-bundle screen. */
    onDiagnostics: (() -> Unit)? = null,
) {
    val context = LocalContext.current
    val snackbarHostState = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()

    val pkgInfo = remember(context) {
        runCatching { context.packageManager.getPackageInfo(context.packageName, 0) }.getOrNull()
    }

    Scaffold(
        topBar = {
            CenterAlignedTopAppBar(
                title = { Text("About") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            // App identity card
            OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text("Bizarre CRM", style = MaterialTheme.typography.titleMedium)
                    Text(
                        "Version ${pkgInfo?.versionName ?: BuildConfig.VERSION_NAME}" +
                            " (build ${pkgInfo?.longVersionCode ?: BuildConfig.VERSION_CODE})",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        "Repair-shop CRM for the real world.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            // Action rows
            OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                Column {
                    AppInfoRow(
                        icon = { Icon(Icons.Default.Star, contentDescription = "Rate app") },
                        title = "Rate Bizarre CRM",
                        subtitle = "Leave a review on the Play Store",
                        onClick = {
                            launchRateApp(context) {
                                scope.launch { snackbarHostState.showSnackbar("Could not open Play Store") }
                            }
                        },
                    )
                    AppInfoRow(
                        icon = { Icon(Icons.Default.Description, contentDescription = "Privacy policy") },
                        title = "Privacy policy",
                        subtitle = "How we handle your data",
                        onClick = {
                            launchUrl(context, PRIVACY_POLICY_URL) {
                                scope.launch { snackbarHostState.showSnackbar("Could not open browser") }
                            }
                        },
                    )
                    AppInfoRow(
                        icon = { Icon(Icons.Default.Gavel, contentDescription = "Terms of service") },
                        title = "Terms of service",
                        subtitle = "Usage terms and conditions",
                        onClick = {
                            launchUrl(context, TERMS_URL) {
                                scope.launch { snackbarHostState.showSnackbar("Could not open browser") }
                            }
                        },
                    )
                    AppInfoRow(
                        icon = { Icon(Icons.Default.Info, contentDescription = "Open-source licenses") },
                        title = "Open-source licenses",
                        subtitle = "Libraries used in this app",
                        onClick = { launchOssLicenses(context) },
                    )
                    if (onDiagnostics != null) {
                        AppInfoRow(
                            icon = {
                                Icon(Icons.Default.BugReport, contentDescription = "Diagnostics")
                            },
                            title = "Diagnostics",
                            subtitle = "Copy support bundle",
                            onClick = onDiagnostics,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun AppInfoRow(
    icon: @Composable () -> Unit,
    title: String,
    subtitle: String,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onClick() }
            .semantics(mergeDescendants = true) { role = Role.Button }
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        CompositionLocalProvider(
            LocalContentColor provides MaterialTheme.colorScheme.onSurfaceVariant,
        ) {
            icon()
        }
        Column(modifier = Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyMedium)
            Text(
                subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Icon(
            Icons.AutoMirrored.Filled.KeyboardArrowRight,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.secondary,
            modifier = Modifier.size(20.dp),
        )
    }
}

// ── helpers ──────────────────────────────────────────────────────────────────

private const val PRIVACY_POLICY_URL = "https://bizarreelectronics.com/privacy"
private const val TERMS_URL = "https://bizarreelectronics.com/terms"
private const val PLAY_STORE_PACKAGE = "com.bizarreelectronics.crm"

private fun launchUrl(context: Context, url: String, onFailure: () -> Unit) {
    try {
        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        })
    } catch (_: ActivityNotFoundException) {
        onFailure()
    }
}

private fun launchOssLicenses(context: Context) {
    // OssLicensesMenuActivity from play-services-oss-licenses.
    // If the dependency is absent the intent falls through silently.
    try {
        val intent = Intent().apply {
            setClassName(
                context.packageName,
                "com.google.android.gms.oss.licenses.OssLicensesMenuActivity",
            )
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
    } catch (_: Exception) {
        // OssLicensesMenuActivity not available (e.g. pure FOSS build without play services).
    }
}

private fun launchRateApp(context: Context, onFailure: () -> Unit) {
    // Try Play Store in-app; fall back to browser link.
    try {
        context.startActivity(
            Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$PLAY_STORE_PACKAGE")).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
        )
    } catch (_: ActivityNotFoundException) {
        launchUrl(
            context,
            "https://play.google.com/store/apps/details?id=$PLAY_STORE_PACKAGE",
            onFailure,
        )
    }
}
