package com.bizarreelectronics.crm.ui.screens.settings

// §2.18 L417-L426 — Manage 2FA Factors settings screen.
//
// Layout:
//   TopAppBar "Manage 2FA factors" + back.
//   Security baseline banner (N factors; warning color when N < 2).
//   Section "Current factors" — enrolled factors list (type icon, label, enrolled-at, Primary badge).
//     No delete/disable button anywhere — USER DIRECTIVE 2026-04-23.
//   Section "Available factors" — factor types NOT yet enrolled, each with an Enroll button.
//     TOTP  → NavigateToTotpEnroll event → caller navigates to QR enroll step.
//     SMS   → PromptSmsPhone event → bottom-sheet phone dialog → enrollSmsWithPhone().
//     Passkey / Hardware key → ComingSoon event → bottom sheet stub (Credential Manager deferred).
//
// Role gate (L417): the SecurityScreen route gates this row for Owner/Manager/Admin.
// This screen itself does not re-enforce role — it relies on the SecurityScreen
// gate. If role gating is not wired at the call site, all authenticated users see the screen.
// See SecurityScreen for the onManageTwoFactorFactors callback gating.

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Fingerprint
import androidx.compose.material.icons.filled.Key
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material.icons.filled.Sms
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Badge
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.data.remote.dto.TwoFactorFactorDto
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import kotlinx.coroutines.launch

// ---------------------------------------------------------------------------
// Known factor types
// ---------------------------------------------------------------------------

private val ALL_FACTOR_TYPES = listOf("totp", "sms", "hardware_key", "passkey")

private fun factorDisplayName(type: String): String = when (type) {
    "totp" -> "Authenticator App (TOTP)"
    "sms" -> "SMS One-Time Code"
    "hardware_key" -> "Hardware Security Key"
    "passkey" -> "Passkey"
    else -> type
}

private fun factorDescription(type: String): String = when (type) {
    "totp" -> "Use Google Authenticator, Authy, or any TOTP app to generate codes."
    "sms" -> "Receive a one-time code via text message to your phone."
    "hardware_key" -> "Use a FIDO2-compatible hardware key (e.g. YubiKey)."
    "passkey" -> "Use a device passkey or platform biometric for sign-in."
    else -> ""
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TwoFactorFactorsScreen(
    onBack: () -> Unit,
    onNavigateToTotpEnroll: () -> Unit,
    viewModel: TwoFactorFactorsViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()

    // Bottom-sheet state for SMS phone prompt
    val smsSheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var showSmsSheet by remember { mutableStateOf(false) }

    // Bottom-sheet state for coming-soon stub (passkey / hardware_key)
    val comingSoonSheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var showComingSoonSheet by remember { mutableStateOf(false) }
    var comingSoonType by remember { mutableStateOf("") }

    // Collect one-shot events
    LaunchedEffect(Unit) {
        viewModel.events.collect { event ->
            when (event) {
                is TwoFactorFactorsEvent.NavigateToTotpEnroll -> onNavigateToTotpEnroll()
                is TwoFactorFactorsEvent.PromptSmsPhone -> {
                    showSmsSheet = true
                }
                is TwoFactorFactorsEvent.ComingSoon -> {
                    comingSoonType = event.type
                    showComingSoonSheet = true
                }
                is TwoFactorFactorsEvent.Toast -> {
                    snackbarHostState.showSnackbar(event.message)
                }
            }
        }
    }

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Manage 2FA factors",
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
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
            when (val state = uiState) {
                is TwoFactorFactorsUiState.Idle,
                is TwoFactorFactorsUiState.Loading -> {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator()
                    }
                }

                is TwoFactorFactorsUiState.Content -> {
                    FactorsContent(
                        factors = state.factors,
                        onEnroll = { type -> viewModel.enrollFactor(type) },
                    )
                }

                is TwoFactorFactorsUiState.NotSupported -> {
                    FactorsNotSupportedContent()
                }

                is TwoFactorFactorsUiState.Error -> {
                    FactorsErrorContent(
                        message = state.error.message,
                        onRetry = { viewModel.refresh() },
                        onDismiss = onBack,
                    )
                }
            }
        }
    }

    // ── SMS phone prompt bottom sheet ──
    if (showSmsSheet) {
        SmsPhoneSheet(
            sheetState = smsSheetState,
            onConfirm = { phone ->
                scope.launch { smsSheetState.hide() }
                    .invokeOnCompletion { showSmsSheet = false }
                viewModel.enrollSmsWithPhone(phone)
            },
            onDismiss = {
                scope.launch { smsSheetState.hide() }
                    .invokeOnCompletion { showSmsSheet = false }
            },
        )
    }

    // ── Coming-soon stub bottom sheet (passkey / hardware_key) ──
    if (showComingSoonSheet) {
        ComingSoonSheet(
            type = comingSoonType,
            sheetState = comingSoonSheetState,
            onDismiss = {
                scope.launch { comingSoonSheetState.hide() }
                    .invokeOnCompletion { showComingSoonSheet = false }
            },
        )
    }
}

// ---------------------------------------------------------------------------
// Content: factor list
// ---------------------------------------------------------------------------

@Composable
private fun FactorsContent(
    factors: List<TwoFactorFactorDto>,
    onEnroll: (String) -> Unit,
) {
    val enrolledTypes = factors.map { it.type }.toSet()
    val availableTypes = ALL_FACTOR_TYPES.filter { it !in enrolledTypes }
    val factorCount = factors.size

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        // ── Security baseline banner ──
        SecurityBaselineBanner(factorCount = factorCount)

        // ── Current factors ──
        if (factors.isNotEmpty()) {
            Text(
                "Current factors",
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(vertical = 4.dp)) {
                    factors.forEachIndexed { index, factor ->
                        EnrolledFactorRow(factor = factor)
                        if (index < factors.lastIndex) {
                            androidx.compose.material3.HorizontalDivider(
                                modifier = Modifier.padding(horizontal = 16.dp),
                                color = MaterialTheme.colorScheme.outline.copy(alpha = 0.4f),
                            )
                        }
                    }
                }
            }
        }

        // ── Available factors to enroll ──
        if (availableTypes.isNotEmpty()) {
            Text(
                "Available factors",
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(vertical = 4.dp)) {
                    availableTypes.forEachIndexed { index, type ->
                        AvailableFactorRow(
                            type = type,
                            onEnroll = { onEnroll(type) },
                        )
                        if (index < availableTypes.lastIndex) {
                            androidx.compose.material3.HorizontalDivider(
                                modifier = Modifier.padding(horizontal = 16.dp),
                                color = MaterialTheme.colorScheme.outline.copy(alpha = 0.4f),
                            )
                        }
                    }
                }
            }
        }

        if (factors.isNotEmpty() && availableTypes.isEmpty()) {
            Text(
                "All supported factor types are enrolled.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

// ---------------------------------------------------------------------------
// Security baseline banner
// ---------------------------------------------------------------------------

@Composable
private fun SecurityBaselineBanner(factorCount: Int) {
    val belowBaseline = factorCount < 2
    val containerColor = if (belowBaseline) {
        MaterialTheme.colorScheme.errorContainer
    } else {
        MaterialTheme.colorScheme.surfaceVariant
    }
    val contentColor = if (belowBaseline) {
        MaterialTheme.colorScheme.onErrorContainer
    } else {
        MaterialTheme.colorScheme.onSurfaceVariant
    }

    Surface(
        color = containerColor,
        shape = MaterialTheme.shapes.small,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            modifier = Modifier.padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            if (belowBaseline) {
                Icon(
                    Icons.Default.Warning,
                    contentDescription = null,
                    modifier = Modifier.size(18.dp),
                    tint = contentColor,
                )
            }
            Text(
                text = if (belowBaseline) {
                    "2 factors required for our security baseline. " +
                        "You currently have $factorCount factor${if (factorCount == 1) "" else "s"}."
                } else {
                    "You have $factorCount factor${if (factorCount == 1) "" else "s"} enrolled — " +
                        "meeting the security baseline."
                },
                style = MaterialTheme.typography.bodySmall,
                color = contentColor,
            )
        }
    }
}

// ---------------------------------------------------------------------------
// Enrolled factor row
// ---------------------------------------------------------------------------

@Composable
private fun EnrolledFactorRow(factor: TwoFactorFactorDto) {
    val icon = when (factor.type) {
        "totp" -> Icons.Default.Shield
        "sms" -> Icons.Default.Sms
        "hardware_key" -> Icons.Default.Key
        "passkey" -> Icons.Default.Fingerprint
        else -> Icons.Default.Shield
    }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            icon,
            contentDescription = null,
            modifier = Modifier.size(20.dp),
            tint = MaterialTheme.colorScheme.primary,
        )
        Spacer(Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Text(
                    factorDisplayName(factor.type),
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium,
                )
                if (factor.isPrimary) {
                    Badge(
                        containerColor = MaterialTheme.colorScheme.primaryContainer,
                        contentColor = MaterialTheme.colorScheme.onPrimaryContainer,
                    ) {
                        Text("Primary", style = MaterialTheme.typography.labelSmall)
                    }
                }
            }
            if (!factor.label.isNullOrBlank()) {
                Text(
                    factor.label,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (!factor.enrolledAt.isNullOrBlank()) {
                Text(
                    "Enrolled ${factor.enrolledAt}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        // NOTE: No delete/disable button here — USER DIRECTIVE 2026-04-23.
        // Factor removal is a server-admin action only.
    }
}

// ---------------------------------------------------------------------------
// Available factor row
// ---------------------------------------------------------------------------

@Composable
private fun AvailableFactorRow(type: String, onEnroll: () -> Unit) {
    val icon = when (type) {
        "totp" -> Icons.Default.Shield
        "sms" -> Icons.Default.Sms
        "hardware_key" -> Icons.Default.Key
        "passkey" -> Icons.Default.Fingerprint
        else -> Icons.Default.Shield
    }
    // Passkey and hardware_key are stubs — gray out enroll button + show [~] note.
    val isDeferred = type == "passkey" || type == "hardware_key"

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            icon,
            contentDescription = null,
            modifier = Modifier.size(20.dp),
            tint = if (isDeferred) {
                MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f)
            } else {
                MaterialTheme.colorScheme.onSurfaceVariant
            },
        )
        Spacer(Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                factorDisplayName(type),
                style = MaterialTheme.typography.bodyMedium,
                color = if (isDeferred) {
                    MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f)
                } else {
                    MaterialTheme.colorScheme.onSurface
                },
            )
            Text(
                factorDescription(type),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(
                    alpha = if (isDeferred) 0.5f else 1f
                ),
            )
        }
        Spacer(Modifier.width(8.dp))
        OutlinedButton(
            onClick = onEnroll,
            // Deferred types still show the button so the user sees the coming-soon sheet.
        ) {
            Text(
                if (isDeferred) "Coming soon" else "Enroll",
                style = MaterialTheme.typography.labelMedium,
                color = if (isDeferred) {
                    MaterialTheme.colorScheme.onSurface.copy(alpha = 0.4f)
                } else {
                    MaterialTheme.colorScheme.primary
                },
            )
        }
    }
}

// ---------------------------------------------------------------------------
// NotSupported content
// ---------------------------------------------------------------------------

@Composable
private fun FactorsNotSupportedContent() {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Card(
            modifier = Modifier.fillMaxWidth(),
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.surfaceVariant,
            ),
        ) {
            Column(
                modifier = Modifier.padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(
                    "Not available",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    "Factor management not available on this server version. " +
                        "Contact your administrator to update the server.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Error content
// ---------------------------------------------------------------------------

@Composable
private fun FactorsErrorContent(
    message: String,
    onRetry: () -> Unit,
    onDismiss: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Card(
            modifier = Modifier.fillMaxWidth(),
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.errorContainer,
            ),
        ) {
            Column(
                modifier = Modifier.padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(
                    "Something went wrong",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onErrorContainer,
                )
                Text(
                    message,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onErrorContainer,
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(onClick = onRetry) { Text("Retry") }
                    TextButton(onClick = onDismiss) { Text("Dismiss") }
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// SMS phone prompt bottom sheet
// ---------------------------------------------------------------------------

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SmsPhoneSheet(
    sheetState: androidx.compose.material3.SheetState,
    onConfirm: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    var phone by remember { mutableStateOf("") }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 24.dp)
                .padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                "Enroll SMS factor",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                "Enter your phone number in E.164 format (e.g. +15551234567). " +
                    "A one-time code will be sent to confirm enrollment.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            OutlinedTextField(
                value = phone,
                onValueChange = { phone = it },
                label = { Text("Phone number") },
                placeholder = { Text("+15551234567") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone),
                modifier = Modifier.fillMaxWidth(),
            )
            Button(
                onClick = { onConfirm(phone) },
                enabled = phone.isNotBlank(),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text("Send verification code")
            }
            TextButton(
                onClick = onDismiss,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text("Cancel")
            }
            Spacer(Modifier.height(8.dp))
        }
    }
}

// ---------------------------------------------------------------------------
// Coming-soon stub bottom sheet (passkey / hardware_key)
// ---------------------------------------------------------------------------

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ComingSoonSheet(
    type: String,
    sheetState: androidx.compose.material3.SheetState,
    onDismiss: () -> Unit,
) {
    val title = when (type) {
        "passkey" -> "Passkey sign-in is coming soon"
        "hardware_key" -> "Hardware key support is coming soon"
        else -> "Coming soon"
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 24.dp)
                .padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                title,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                "Passkey sign-in is coming soon. For now, use TOTP + recovery codes " +
                    "for the best 2FA security. Hardware key (FIDO2) and platform passkey " +
                    "support via Android Credential Manager is planned for a future release.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Button(
                onClick = onDismiss,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text("Got it")
            }
            Spacer(Modifier.height(8.dp))
        }
    }
}
