package com.bizarreelectronics.crm.ui.screens.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.ManageAccounts
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp

/**
 * §19.11 — Team / Roles settings hub.
 *
 * Provides deep-link navigation to the Employee list (§14) and Custom
 * Roles matrix editor (§49). Admin-only; enforced at the nav call site.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TeamSettingsScreen(
    onBack: () -> Unit,
    /** Navigate to the Employee list screen (§14). */
    onEmployees: (() -> Unit)? = null,
    /** Navigate to the Custom Roles editor (§49). */
    onCustomRoles: (() -> Unit)? = null,
) {
    Scaffold(
        topBar = {
            CenterAlignedTopAppBar(
                title = { Text("Team & Roles") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
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
                Column {
                    Text(
                        "Team management",
                        style = MaterialTheme.typography.titleSmall,
                        modifier = Modifier.padding(start = 16.dp, top = 16.dp, end = 16.dp),
                    )
                    if (onEmployees != null) {
                        ListItem(
                            leadingContent = {
                                Icon(Icons.Default.Group, contentDescription = "Employees")
                            },
                            headlineContent = { Text("Employees") },
                            supportingContent = { Text("Manage staff accounts, timeclock, roles") },
                            modifier = Modifier
                                .clickable { onEmployees() }
                                .semantics(mergeDescendants = true) { role = Role.Button },
                        )
                    }
                    if (onCustomRoles != null) {
                        ListItem(
                            leadingContent = {
                                Icon(Icons.Default.ManageAccounts, contentDescription = "Custom roles")
                            },
                            headlineContent = { Text("Custom roles") },
                            supportingContent = { Text("Define permission sets for each role") },
                            modifier = Modifier
                                .clickable { onCustomRoles() }
                                .semantics(mergeDescendants = true) { role = Role.Button },
                        )
                    }
                    if (onEmployees == null && onCustomRoles == null) {
                        Text(
                            "Team management features are available to admins.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(16.dp),
                        )
                    }
                }
            }
        }
    }
}
