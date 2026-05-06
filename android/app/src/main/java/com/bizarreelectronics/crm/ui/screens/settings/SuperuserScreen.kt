package com.bizarreelectronics.crm.ui.screens.settings

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.browser.customtabs.CustomTabsIntent
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
import androidx.compose.material.icons.filled.Assessment
import androidx.compose.material.icons.filled.Business
import androidx.compose.material.icons.filled.CloudDownload
import androidx.compose.material.icons.filled.CloudUpload
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.ManageAccounts
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Storage
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch

private enum class SuperuserDestination {
    Android,
    Web,
}

private data class SuperuserFeature(
    val title: String,
    val subtitle: String,
    val icon: ImageVector,
    val destination: SuperuserDestination,
    val route: String? = null,
    val webPath: String? = null,
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SuperuserScreen(
    onBack: () -> Unit,
    onNavigate: (String) -> Unit,
    serverUrl: String?,
    userRole: String?,
) {
    val context = LocalContext.current
    val snackbarHostState = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()
    val roleLabel = remember(userRole) {
        userRole
            ?.takeIf { it.isNotBlank() }
            ?.replaceFirstChar { it.uppercase() }
            ?: "Unknown"
    }

    fun openWeb(path: String) {
        val url = buildWebUrl(serverUrl, path)
        if (url == null) {
            scope.launch { snackbarHostState.showSnackbar("Server URL is not configured") }
            return
        }
        launchBrowser(context, url) {
            scope.launch { snackbarHostState.showSnackbar("Could not open browser") }
        }
    }

    Scaffold(
        topBar = {
            CenterAlignedTopAppBar(
                title = { Text("Superuser") },
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
            OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Text("Advanced access", style = MaterialTheme.typography.titleMedium)
                    Text(
                        "Current role: $roleLabel",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        "This hub shows where advanced tools live today. " +
                            "Android rows open in the app; web rows open the configured web admin.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            SuperuserSection(
                title = "Available in Android",
                features = androidFeatures,
                onFeatureClick = { feature ->
                    feature.route?.let(onNavigate)
                },
            )

            SuperuserSection(
                title = "Web admin",
                features = webFeatures,
                onFeatureClick = { feature ->
                    feature.webPath?.let(::openWeb)
                },
            )
        }
    }
}

@Composable
private fun SuperuserSection(
    title: String,
    features: List<SuperuserFeature>,
    onFeatureClick: (SuperuserFeature) -> Unit,
) {
    OutlinedCard(modifier = Modifier.fillMaxWidth()) {
        Column {
            Text(
                title,
                style = MaterialTheme.typography.titleSmall,
                modifier = Modifier.padding(start = 16.dp, top = 16.dp, end = 16.dp),
            )
            features.forEachIndexed { index, feature ->
                SuperuserFeatureRow(
                    feature = feature,
                    onClick = { onFeatureClick(feature) },
                )
                if (index < features.lastIndex) {
                    HorizontalDivider(
                        color = MaterialTheme.colorScheme.outline.copy(alpha = 0.35f),
                        thickness = 1.dp,
                        modifier = Modifier.padding(horizontal = 16.dp),
                    )
                }
            }
        }
    }
}

@Composable
private fun SuperuserFeatureRow(
    feature: SuperuserFeature,
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
        CompositionLocalProvider(LocalContentColor provides MaterialTheme.colorScheme.onSurfaceVariant) {
            Icon(feature.icon, contentDescription = null, modifier = Modifier.size(22.dp))
        }
        Column(modifier = Modifier.weight(1f)) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(
                    feature.title,
                    style = MaterialTheme.typography.bodyMedium,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )
                DestinationChip(feature.destination)
            }
            Text(
                feature.subtitle,
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

@Composable
private fun DestinationChip(destination: SuperuserDestination) {
    val label = when (destination) {
        SuperuserDestination.Android -> "Android"
        SuperuserDestination.Web -> "Web"
    }
    val container = when (destination) {
        SuperuserDestination.Android -> MaterialTheme.colorScheme.secondaryContainer
        SuperuserDestination.Web -> MaterialTheme.colorScheme.tertiaryContainer
    }
    val content = when (destination) {
        SuperuserDestination.Android -> MaterialTheme.colorScheme.onSecondaryContainer
        SuperuserDestination.Web -> MaterialTheme.colorScheme.onTertiaryContainer
    }
    Surface(
        color = container,
        contentColor = content,
        shape = MaterialTheme.shapes.small,
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
        )
    }
}

private val androidFeatures = listOf(
    SuperuserFeature(
        title = "Audit logs",
        subtitle = "Security and change history for admin review",
        icon = Icons.Default.History,
        destination = SuperuserDestination.Android,
        route = "audit-logs",
    ),
    SuperuserFeature(
        title = "Team and roles",
        subtitle = "Employees, custom roles, and permission management",
        icon = Icons.Default.ManageAccounts,
        destination = SuperuserDestination.Android,
        route = "settings/team",
    ),
    SuperuserFeature(
        title = "Data import",
        subtitle = "Import supported shop data into Android",
        icon = Icons.Default.CloudUpload,
        destination = SuperuserDestination.Android,
        route = "data-import",
    ),
    SuperuserFeature(
        title = "Data export",
        subtitle = "Export tenant data where mobile export is supported",
        icon = Icons.Default.CloudDownload,
        destination = SuperuserDestination.Android,
        route = "data-export",
    ),
    SuperuserFeature(
        title = "Financial dashboard",
        subtitle = "Owner-only financial reporting surface",
        icon = Icons.Default.Assessment,
        destination = SuperuserDestination.Android,
        route = "financial-dashboard",
    ),
    SuperuserFeature(
        title = "Device templates",
        subtitle = "Reusable repair device templates",
        icon = Icons.Default.Settings,
        destination = SuperuserDestination.Android,
        route = "settings/device-templates",
    ),
    SuperuserFeature(
        title = "Repair pricing",
        subtitle = "Repair services catalog and default prices",
        icon = Icons.Default.CreditCard,
        destination = SuperuserDestination.Android,
        route = "settings/repair-pricing",
    ),
)

private val webFeatures = listOf(
    SuperuserFeature(
        title = "Web dashboard",
        subtitle = "Full desktop dashboard and web-only navigation",
        icon = Icons.Default.Assessment,
        destination = SuperuserDestination.Web,
        webPath = "/",
    ),
    SuperuserFeature(
        title = "Super-admin tenants",
        subtitle = "Tenant provisioning and cross-tenant operations",
        icon = Icons.Default.Business,
        destination = SuperuserDestination.Web,
        webPath = "/super-admin/tenants",
    ),
    SuperuserFeature(
        title = "Billing and plan",
        subtitle = "Subscription, usage, and upgrade controls",
        icon = Icons.Default.CreditCard,
        destination = SuperuserDestination.Web,
        webPath = "/settings/billing",
    ),
    SuperuserFeature(
        title = "Automations",
        subtitle = "Rules, triggers, and workflow automation",
        icon = Icons.Default.Settings,
        destination = SuperuserDestination.Web,
        webPath = "/settings/automations",
    ),
    SuperuserFeature(
        title = "Data retention and danger zone",
        subtitle = "Retention, account closure, and high-risk account tools",
        icon = Icons.Default.Storage,
        destination = SuperuserDestination.Web,
        webPath = "/settings/danger-zone",
    ),
)

private fun buildWebUrl(serverUrl: String?, path: String): String? {
    val base = serverUrl
        ?.trim()
        ?.trimEnd('/')
        ?.takeIf { it.startsWith("http://") || it.startsWith("https://") }
        ?: return null
    val webBase = base.removeSuffix("/api/v1").removeSuffix("/api")
    val normalizedPath = when {
        path == "/" -> ""
        path.startsWith("/") -> path
        else -> "/$path"
    }
    return "$webBase$normalizedPath"
}

private fun launchBrowser(context: Context, url: String, onFailure: () -> Unit) {
    val uri = Uri.parse(url)
    try {
        CustomTabsIntent.Builder().build().launchUrl(context, uri)
    } catch (_: ActivityNotFoundException) {
        launchBrowserChooser(context, uri, onFailure)
    }
}

private fun launchBrowserChooser(context: Context, uri: Uri, onFailure: () -> Unit) {
    try {
        val browserIntent = Intent(Intent.ACTION_VIEW, uri).apply {
            addCategory(Intent.CATEGORY_BROWSABLE)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(
            Intent.createChooser(browserIntent, "Open web admin").apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            },
        )
    } catch (_: ActivityNotFoundException) {
        onFailure()
    }
}
