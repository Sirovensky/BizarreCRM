package com.bizarreelectronics.crm.ui.screens.settings

import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Policy
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.Card
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import com.bizarreelectronics.crm.BuildConfig
import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.util.ClipboardUtil
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * §28 / §32 — Settings → About / Diagnostics surface.
 *
 * Shows app + device + tenant info that support staff routinely ask for so
 * the user can copy a single bundle into a ticket / email instead of hunting
 * through five system screens. Read-only; no destructive actions live here.
 */
data class AboutInfo(
    val appName: String,
    val versionName: String,
    val versionCode: Int,
    val buildType: String,
    val packageName: String,
    val deviceModel: String,
    val androidVersion: String,
    val sdk: Int,
    val serverUrl: String,
    val username: String,
    val role: String,
    val installId: String,
)

@HiltViewModel
class AboutViewModel @Inject constructor(
    private val authPreferences: AuthPreferences,
    private val appPreferences: AppPreferences,
    private val breadcrumbs: com.bizarreelectronics.crm.util.Breadcrumbs,
) : ViewModel() {
    fun snapshot(): AboutInfo = AboutInfo(
        appName = "Bizarre CRM",
        versionName = BuildConfig.VERSION_NAME,
        versionCode = BuildConfig.VERSION_CODE,
        buildType = if (BuildConfig.DEBUG) "debug" else "release",
        packageName = "com.bizarreelectronics.crm",
        deviceModel = "${Build.MANUFACTURER} ${Build.MODEL}",
        androidVersion = Build.VERSION.RELEASE,
        sdk = Build.VERSION.SDK_INT,
        serverUrl = authPreferences.serverUrl ?: "(not set)",
        username = authPreferences.username ?: "(not signed in)",
        role = authPreferences.userRole ?: "—",
        installId = authPreferences.installationId,
    )

    fun recentBreadcrumbs(): List<String> = breadcrumbs.recent()

    // §19.14 — privacy policy URL from auth prefs server URL (or fallback)
    fun privacyPolicyUrl(): String {
        val server = authPreferences.serverUrl?.trimEnd('/')
        return if (!server.isNullOrBlank()) "$server/privacy" else "https://bizarrecrm.com/privacy"
    }

    fun termsUrl(): String {
        val server = authPreferences.serverUrl?.trimEnd('/')
        return if (!server.isNullOrBlank()) "$server/terms" else "https://bizarrecrm.com/terms"
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AboutScreen(
    onBack: () -> Unit,
    viewModel: AboutViewModel = hiltViewModel(),
) {
    val context = LocalContext.current
    val info = remember { viewModel.snapshot() }
    val crumbs = remember { viewModel.recentBreadcrumbs() }
    val snackbarHostState = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()
    val bundle = remember(info, crumbs) { renderBundle(info, crumbs) }
    val privacyUrl = remember { viewModel.privacyPolicyUrl() }
    val termsUrl = remember { viewModel.termsUrl() }

    Scaffold(
        topBar = {
            CenterAlignedTopAppBar(
                title = { Text("About") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    IconButton(onClick = {
                        ClipboardUtil.copy(context, "Bizarre CRM diagnostics", bundle)
                        scope.launch {
                            snackbarHostState.showSnackbar("Diagnostics copied to clipboard")
                        }
                    }) {
                        Icon(Icons.Default.ContentCopy, contentDescription = "Copy diagnostics")
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
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("App", style = MaterialTheme.typography.titleSmall)
                    KeyValueRow("Name", info.appName)
                    KeyValueRow("Version", "${info.versionName} (${info.versionCode}, ${info.buildType})")
                    KeyValueRow("Package", info.packageName)
                }
            }
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Device", style = MaterialTheme.typography.titleSmall)
                    KeyValueRow("Model", info.deviceModel)
                    KeyValueRow("Android", "${info.androidVersion} (SDK ${info.sdk})")
                }
            }
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Tenant", style = MaterialTheme.typography.titleSmall)
                    KeyValueRow("Server", info.serverUrl)
                    KeyValueRow("Signed in as", info.username)
                    KeyValueRow("Role", info.role)
                    KeyValueRow("Install ID", info.installId, mono = true)
                }
            }
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(
                        "Recent activity (last ${crumbs.size})",
                        style = MaterialTheme.typography.titleSmall,
                    )
                    if (crumbs.isEmpty()) {
                        Text(
                            "No breadcrumbs yet — this fills as you navigate the app.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    } else {
                        crumbs.takeLast(20).forEach { line ->
                            Text(
                                text = line,
                                style = MaterialTheme.typography.bodySmall,
                                fontFamily = FontFamily.Monospace,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
            }

            // §19.14 — Legal + store links
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(0.dp)) {
                    Text("Legal & links", style = MaterialTheme.typography.titleSmall)
                    androidx.compose.foundation.layout.Spacer(Modifier.size(8.dp))

                    // OSS licenses — OssLicensesMenuActivity from play-services-oss-licenses
                    AboutLinkRow(
                        icon = Icons.Default.Description,
                        label = "Open-source licenses",
                        onClick = {
                            runCatching {
                                val intent = Intent(context, Class.forName("com.google.android.gms.oss.licenses.OssLicensesMenuActivity"))
                                context.startActivity(intent)
                            }.onFailure {
                                scope.launch {
                                    snackbarHostState.showSnackbar("OSS licenses activity not available in this build")
                                }
                            }
                        },
                    )

                    androidx.compose.material3.HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.3f))

                    // Privacy policy — opens browser to server /privacy or fallback URL
                    AboutLinkRow(
                        icon = Icons.Default.Policy,
                        label = "Privacy policy",
                        onClick = {
                            runCatching {
                                context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(privacyUrl)))
                            }
                        },
                    )

                    androidx.compose.material3.HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.3f))

                    // Terms of service
                    AboutLinkRow(
                        icon = Icons.Default.Description,
                        label = "Terms of service",
                        onClick = {
                            runCatching {
                                context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(termsUrl)))
                            }
                        },
                    )

                    androidx.compose.material3.HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.3f))

                    // Rate app — Play in-app review flow (ReviewManagerFactory via reflection;
                    // falls back to Play Store browser link if play-core not in classpath).
                    AboutLinkRow(
                        icon = Icons.Default.Star,
                        label = "Rate app",
                        onClick = {
                            val launched = runCatching {
                                val factoryClass = Class.forName("com.google.android.play.core.review.ReviewManagerFactory")
                                val createMethod = factoryClass.getMethod("create", android.content.Context::class.java)
                                val manager = createMethod.invoke(null, context)
                                val requestMethod = manager.javaClass.getMethod("requestReviewFlow")
                                @Suppress("UNCHECKED_CAST")
                                val task = requestMethod.invoke(manager) as? com.google.android.gms.tasks.Task<*>
                                task?.addOnCompleteListener { t ->
                                    if (t.isSuccessful) {
                                        val activity = context as? android.app.Activity
                                        if (activity != null) {
                                            val launchMethod = manager.javaClass.getMethod("launchReviewFlow", android.app.Activity::class.java, t.result!!.javaClass)
                                            runCatching { launchMethod.invoke(manager, activity, t.result) }
                                        }
                                    }
                                }
                                true
                            }.getOrElse { false }
                            if (!launched) {
                                // Fallback: open Play Store listing in browser
                                runCatching {
                                    context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=${context.packageName}")))
                                }.onFailure {
                                    runCatching {
                                        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://play.google.com/store/apps/details?id=${context.packageName}")))
                                    }
                                }
                            }
                        },
                    )
                }
            }
        }
    }
}

/**
 * §19.14 — Single tappable row in the Legal section.
 */
@Composable
private fun AboutLinkRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onClick() }
            .semantics(mergeDescendants = true) { role = Role.Button }
            .padding(vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, contentDescription = null, modifier = Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.width(12.dp))
        Text(label, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(18.dp))
    }
}

@Composable
private fun KeyValueRow(label: String, value: String, mono: Boolean = false) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.weight(0.4f),
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium,
            fontFamily = if (mono) FontFamily.Monospace else null,
            modifier = Modifier.weight(0.6f),
        )
    }
}

private fun renderBundle(info: AboutInfo, crumbs: List<String>): String = buildString {
    appendLine("Bizarre CRM diagnostics")
    appendLine()
    appendLine("App:    ${info.versionName} (${info.versionCode}, ${info.buildType})")
    appendLine("Pkg:    ${info.packageName}")
    appendLine("Device: ${info.deviceModel}")
    appendLine("OS:     Android ${info.androidVersion} (SDK ${info.sdk})")
    appendLine("Server: ${info.serverUrl}")
    appendLine("User:   ${info.username} (${info.role})")
    appendLine("Inst:   ${info.installId}")
    if (crumbs.isNotEmpty()) {
        appendLine()
        appendLine("--- Recent activity (last ${crumbs.size}) ---")
        crumbs.forEach { appendLine(it) }
    }
}
