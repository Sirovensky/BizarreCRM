package com.bizarreelectronics.crm.ui.screens.settings

import android.os.Build
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.ContentCopy
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
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AboutScreen(
    onBack: () -> Unit,
    viewModel: AboutViewModel = hiltViewModel(),
) {
    val context = LocalContext.current
    val info = remember { viewModel.snapshot() }
    val snackbarHostState = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()
    val bundle = remember(info) { renderBundle(info) }

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
        }
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

private fun renderBundle(info: AboutInfo): String = buildString {
    appendLine("Bizarre CRM diagnostics")
    appendLine()
    appendLine("App:    ${info.versionName} (${info.versionCode}, ${info.buildType})")
    appendLine("Pkg:    ${info.packageName}")
    appendLine("Device: ${info.deviceModel}")
    appendLine("OS:     Android ${info.androidVersion} (SDK ${info.sdk})")
    appendLine("Server: ${info.serverUrl}")
    appendLine("User:   ${info.username} (${info.role})")
    appendLine("Inst:   ${info.installId}")
}
