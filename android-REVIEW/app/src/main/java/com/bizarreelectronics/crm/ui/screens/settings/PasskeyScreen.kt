package com.bizarreelectronics.crm.ui.screens.settings

import android.app.Activity
import android.os.Build
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Key
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.data.remote.dto.PasskeyCredentialInfo
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.ConfirmDialog
import com.bizarreelectronics.crm.util.PasskeyManager

/**
 * §2.22 — Passkey management screen (Settings > Security > Passkeys).
 *
 * Displays the list of passkeys enrolled for the current account.
 * Each row shows the device name / label and the enrolment date.
 * A "Remove" button triggers a confirm dialog before calling DELETE.
 *
 * "Add passkey" button runs the full begin → enroll → finish handshake via
 * [PasskeyViewModel.startEnrollment] / [PasskeyManager].
 *
 * "Not supported" UI is shown when:
 *  - Device API level < 28 (minSdk for CredentialManager), or
 *  - CredentialManager reports the device does not support passkeys.
 *
 * ## Hardware key (§2.23)
 * CredentialManager's FIDO2 stack includes hardware security keys as a transport.
 * When a user plugs in a YubiKey (USB-C) or taps it (NFC) during the enroll flow
 * the system picker shows it automatically — no extra code required here.
 *
 * ## Password breakglass (L468/L469)
 * Password login is always available as a fallback. Removing password login entirely
 * requires a server endpoint (`DELETE /auth/password`) that is not yet implemented;
 * that follow-up is tracked as a separate item (L469).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PasskeyScreen(
    onBack: () -> Unit,
    viewModel: PasskeyViewModel = hiltViewModel(),
) {
    val context = LocalContext.current
    val activity = context as? Activity
    val uiState by viewModel.uiState.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(uiState.snackbarMessage) {
        val msg = uiState.snackbarMessage ?: return@LaunchedEffect
        snackbarHostState.showSnackbar(msg)
        viewModel.clearSnackbar()
    }

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Passkeys",
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    if (!uiState.isUnsupported) {
                        IconButton(
                            onClick = { activity?.let { viewModel.startEnrollment(it) } },
                            enabled = !uiState.isEnrolling && !uiState.isLoading,
                        ) {
                            Icon(Icons.Default.Add, contentDescription = "Add passkey")
                        }
                    }
                },
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            when {
                uiState.isUnsupported -> UnsupportedContent()
                uiState.isLoading && uiState.passkeys.isEmpty() -> {
                    CircularProgressIndicator(modifier = Modifier.align(Alignment.Center))
                }
                else -> PasskeyListContent(
                    passkeys = uiState.passkeys,
                    isEnrolling = uiState.isEnrolling,
                    onAdd = { activity?.let { viewModel.startEnrollment(it) } },
                    onRequestDelete = { viewModel.requestDelete(it) },
                )
            }
        }
    }

    // Delete confirm dialog.
    val deleteId = uiState.deleteConfirmId
    if (deleteId != null) {
        ConfirmDialog(
            title = "Remove passkey",
            message = "This passkey will be removed from your account. You will no longer be able to sign in with it.",
            confirmLabel = "Remove",
            onConfirm = { viewModel.confirmDelete() },
            onDismiss = { viewModel.dismissDeleteConfirm() },
            isDestructive = true,
        )
    }
}

@Composable
private fun UnsupportedContent() {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Icon(
            Icons.Default.Key,
            contentDescription = null,
            modifier = Modifier.size(48.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(16.dp))
        Text(
            "Passkeys not supported on this device",
            style = MaterialTheme.typography.titleMedium,
        )
        Spacer(Modifier.height(8.dp))
        Text(
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P)
                "Passkeys require Android 9 (API 28) or later."
            else
                "Your device or Google account configuration does not support passkeys.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun PasskeyListContent(
    passkeys: List<PasskeyCredentialInfo>,
    isEnrolling: Boolean,
    onAdd: () -> Unit,
    onRequestDelete: (String) -> Unit,
) {
    LazyColumn(
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (passkeys.isEmpty()) {
            item {
                NoPasskeysCard(isEnrolling = isEnrolling, onAdd = onAdd)
            }
        } else {
            items(passkeys, key = { it.id }) { passkey ->
                PasskeyRow(passkey = passkey, onDelete = { onRequestDelete(passkey.id) })
            }
            item {
                OutlinedButton(
                    onClick = onAdd,
                    enabled = !isEnrolling,
                    modifier = Modifier.fillMaxWidth().height(48.dp),
                ) {
                    if (isEnrolling) {
                        CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                    } else {
                        Icon(Icons.Default.Add, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(8.dp))
                        Text("Add another passkey")
                    }
                }
            }
        }
    }
}

@Composable
private fun NoPasskeysCard(isEnrolling: Boolean, onAdd: () -> Unit) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Icon(
                Icons.Default.Key,
                contentDescription = null,
                modifier = Modifier.size(40.dp),
                tint = MaterialTheme.colorScheme.primary,
            )
            Spacer(Modifier.height(12.dp))
            Text("No passkeys enrolled", style = MaterialTheme.typography.titleSmall)
            Spacer(Modifier.height(4.dp))
            Text(
                "Passkeys let you sign in with your fingerprint, face, or a hardware security key — no password required.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(16.dp))
            Button(
                onClick = onAdd,
                enabled = !isEnrolling,
                modifier = Modifier.fillMaxWidth(),
            ) {
                if (isEnrolling) {
                    CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                } else {
                    Icon(Icons.Default.Add, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(8.dp))
                    Text("Add passkey")
                }
            }
        }
    }
}

@Composable
private fun PasskeyRow(
    passkey: PasskeyCredentialInfo,
    onDelete: () -> Unit,
) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                Icons.Default.Key,
                contentDescription = null,
                modifier = Modifier.size(24.dp),
                tint = MaterialTheme.colorScheme.primary,
            )
            Spacer(Modifier.width(12.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = passkey.deviceName.ifBlank { "Passkey" },
                    style = MaterialTheme.typography.bodyMedium,
                )
                if (!passkey.createdAt.isNullOrBlank()) {
                    Text(
                        text = "Added ${passkey.createdAt}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            IconButton(onClick = onDelete) {
                Icon(
                    Icons.Default.Delete,
                    contentDescription = "Remove passkey ${passkey.deviceName}",
                    tint = MaterialTheme.colorScheme.error,
                )
            }
        }
    }
}
