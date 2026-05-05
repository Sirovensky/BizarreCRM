package com.bizarreelectronics.crm.ui.screens.dashboard.components

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.SwitchAccount
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp

/**
 * §3.9 L549 — Avatar with long-press DropdownMenu.
 *
 * Long-press opens a menu with: Profile, Switch User, Sign Out.
 *
 * Intended for:
 *   - Phone: top-left of the dashboard (inside [BrandTopAppBar] navigation slot)
 *   - Tablet: nav-rail header slot
 *
 * [initials] are derived by the caller from [AuthPreferences] (first char of
 * first + last name, or first char of username as fallback).
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun AvatarLongPressMenu(
    initials: String,
    onNavigateToProfile: (() -> Unit)?,
    onSwitchUser: (() -> Unit)?,
    onSignOut: (() -> Unit)?,
    modifier: Modifier = Modifier,
) {
    var expanded by remember { mutableStateOf(false) }

    Box(modifier = modifier) {
        Box(
            modifier = Modifier
                .size(36.dp)
                .clip(CircleShape)
                .background(MaterialTheme.colorScheme.primaryContainer)
                .semantics {
                    contentDescription = "User avatar — long-press for account menu"
                    role = Role.Button
                }
                .combinedClickable(
                    onClick = { onNavigateToProfile?.invoke() },
                    onLongClick = { expanded = true },
                    onLongClickLabel = "Open account menu",
                ),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = initials.take(2).uppercase(),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onPrimaryContainer,
            )
        }

        DropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false },
        ) {
            if (onNavigateToProfile != null) {
                DropdownMenuItem(
                    text = { Text("Profile") },
                    leadingIcon = {
                        Icon(Icons.Default.Person, contentDescription = null)
                    },
                    onClick = {
                        expanded = false
                        onNavigateToProfile()
                    },
                )
            }
            if (onSwitchUser != null) {
                DropdownMenuItem(
                    text = { Text("Switch user") },
                    leadingIcon = {
                        Icon(Icons.Default.SwitchAccount, contentDescription = null)
                    },
                    onClick = {
                        expanded = false
                        onSwitchUser()
                    },
                )
            }
            if (onSignOut != null) {
                DropdownMenuItem(
                    text = { Text("Sign out") },
                    leadingIcon = {
                        Icon(Icons.AutoMirrored.Filled.Logout, contentDescription = null)
                    },
                    onClick = {
                        expanded = false
                        onSignOut()
                    },
                )
            }
        }
    }
}
