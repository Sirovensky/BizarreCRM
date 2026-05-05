package com.bizarreelectronics.crm.ui.components

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.DialogProperties
import com.bizarreelectronics.crm.data.remote.api.TenantsApi
import com.bizarreelectronics.crm.data.remote.dto.TenantSupportDto

/**
 * Modal shown when the server returns HTTP 423 (Locked) during login
 * (ActionPlan §2.12 L355). Fetches tenant support contact from
 * GET /tenants/me/support-contact; falls back to a generic "Contact your
 * admin." message when the endpoint is unreachable or returns 404.
 *
 * NEVER hardcodes an email address — self-hosted tenants must show their
 * own admin's contact, not a bizarrecrm.com address.
 *
 * Behavior:
 *  - Fetches support contact via [TenantsApi.getSupportContact] on first composition.
 *  - Shows mail intent for [TenantSupportDto.email] when present.
 *  - Shows dial intent for [TenantSupportDto.phone] when present.
 *  - Shows static "Business hours: …" text when [TenantSupportDto.hours] is present.
 *  - Degrades to "Contact your admin." with no intents when fetch fails or dto is null.
 *  - Non-dismissable on backdrop click; back-press closes (dismissOnClickOutside = false,
 *    dismissOnBackPress = true).
 *  - Accessibility: liveRegion = Assertive, Role.AlertDialog, icon contentDescription.
 *
 * @param tenantsApi  Retrofit interface for tenant config. Injected by the caller.
 * @param onDismiss   Invoked when the user taps "Close".
 * @param modifier    Applied to the [AlertDialog] root.
 */
@Composable
fun AccountLockedModal(
    tenantsApi: TenantsApi,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var loadState by rememberSaveable { mutableStateOf<LoadState>(LoadState.Loading) }

    LaunchedEffect(Unit) {
        loadState = try {
            val response = tenantsApi.getSupportContact()
            if (response.success && response.data != null) {
                LoadState.Done(response.data)
            } else {
                // success=false or null data — treat as failed (degraded UI)
                LoadState.Failed
            }
        } catch (_: Exception) {
            // Network error, HTTP 404, or any other failure — degrade gracefully.
            LoadState.Failed
        }
    }

    val context = LocalContext.current

    val dto: TenantSupportDto? = if (loadState is LoadState.Done) {
        (loadState as LoadState.Done).dto
    } else {
        null
    }
    val hasContact = dto?.email != null || dto?.phone != null

    // Build a composite description so accessibility services announce all info.
    val dialogDescription = buildString {
        append("Account locked. Your account is locked. Contact your admin to restore access.")
        if (dto?.email != null) append(" Support email: ${dto.email}.")
        if (dto?.phone != null) append(" Support phone: ${dto.phone}.")
        if (dto?.hours != null) append(" Business hours: ${dto.hours}.")
    }

    AlertDialog(
        onDismissRequest = { /* non-dismissable on backdrop click */ },
        properties = DialogProperties(
            dismissOnClickOutside = false,
            dismissOnBackPress = true,
        ),
        modifier = modifier.semantics {
            role = Role.Image   // closest Role for a modal dialog in Compose semantics
            liveRegion = LiveRegionMode.Assertive
            contentDescription = dialogDescription
        },
        icon = {
            Icon(
                imageVector = Icons.Default.Lock,
                contentDescription = "Lock icon — account locked",
                tint = MaterialTheme.colorScheme.onErrorContainer,
                modifier = Modifier.size(ICON_SIZE_DP.dp),
            )
        },
        title = {
            // TODO(i18n): Extract to string resource.
            Text(
                text = "Account locked",
                style = MaterialTheme.typography.headlineSmall,
                color = MaterialTheme.colorScheme.onSurface,
            )
        },
        text = {
            Column(
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                // Primary copy — always shown.
                // TODO(i18n)
                Text(
                    text = "Your account is locked. Contact your admin to restore access.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )

                when (loadState) {
                    is LoadState.Loading -> {
                        Spacer(modifier = Modifier.height(4.dp))
                        CircularProgressIndicator(
                            modifier = Modifier
                                .size(SPINNER_SIZE_DP.dp)
                                .align(Alignment.CenterHorizontally),
                            strokeWidth = 2.dp,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    is LoadState.Done, LoadState.Failed -> {
                        // Business hours static text — shown when available.
                        if (dto?.hours != null) {
                            // TODO(i18n)
                            Text(
                                text = "Business hours: ${dto.hours}",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }

                        // Contact row: email and/or phone buttons, only when dto is present.
                        if (hasContact) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                            ) {
                                if (dto?.email != null) {
                                    val emailUri = Uri.parse(
                                        "mailto:${dto.email}?subject=Account+locked",
                                    )
                                    TextButton(
                                        onClick = {
                                            context.startActivity(
                                                Intent(Intent.ACTION_SENDTO, emailUri).apply {
                                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                                },
                                            )
                                        },
                                    ) {
                                        // TODO(i18n)
                                        Text(
                                            text = "Email ${dto.email}",
                                            color = MaterialTheme.colorScheme.primary,
                                        )
                                    }
                                }

                                if (dto?.phone != null) {
                                    val telUri = Uri.parse("tel:${dto.phone}")
                                    TextButton(
                                        onClick = {
                                            context.startActivity(
                                                Intent(Intent.ACTION_DIAL, telUri).apply {
                                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                                },
                                            )
                                        },
                                    ) {
                                        // TODO(i18n)
                                        Text(
                                            text = "Call ${dto.phone}",
                                            color = MaterialTheme.colorScheme.primary,
                                        )
                                    }
                                }
                            }
                        }
                        // When !hasContact (Failed or dto has no email/phone): no intents shown.
                        // The primary "Contact your admin" copy above is sufficient.
                    }
                }
            }
        },
        containerColor = MaterialTheme.colorScheme.errorContainer,
        confirmButton = {
            // No "confirm" action — Close is the only button.
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                // TODO(i18n)
                Text(
                    text = "Close",
                    color = MaterialTheme.colorScheme.onErrorContainer,
                )
            }
        },
    )
}

// ---------------------------------------------------------------------------
// Private sealed state
// ---------------------------------------------------------------------------

/**
 * Tracks the lifecycle of the [TenantsApi.getSupportContact] fetch.
 * Uses a sealed class (not enum) so [Done] can carry nullable DTO payload.
 */
private sealed class LoadState {
    data object Loading : LoadState()
    data class Done(val dto: TenantSupportDto?) : LoadState()
    data object Failed : LoadState()
}

// ---------------------------------------------------------------------------
// Private constants
// ---------------------------------------------------------------------------

/** Size of the lock icon in the dialog header, in dp. */
private const val ICON_SIZE_DP = 32

/** Size of the loading spinner shown while the support-contact fetch is in flight, in dp. */
private const val SPINNER_SIZE_DP = 24
