package com.bizarreelectronics.crm.ui.components.shared

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CloudOff
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.SyncProblem
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.R

// NOTE: The base [ErrorState(message, onRetry)] signature lives in SharedComponents.kt
// (same package). This file adds higher-level typed variants that map HTTP error
// categories (network, server, 4xx, 409 conflict, offline-cached) to the correct
// copy from strings.xml and the correct icon, while delegating rendering to the
// base ErrorState.
//
// §66.3 requirements:
//   - Network errors: cached data still shown where possible + banner  → ErrorKind.Network
//   - 4xx errors: user-friendly copy from server `message`            → ErrorKind.Client
//   - 5xx errors: "Something went wrong on our end…" + retry          → ErrorKind.Server
//   - Permission denied: "Ask your admin to enable this."             → ErrorKind.PermissionDenied
//   - 409 conflict: "This item was updated elsewhere. [Reload]"       → ErrorKind.Conflict

/**
 * Discriminated union of error categories for §66.3.
 *
 * @param serverMessage Optional human-readable message returned by the server
 *   (used for [Client] errors where the server provides copy).
 */
sealed class ErrorKind {
    /** Network unreachable / timeout. */
    object Network : ErrorKind()

    /** Server-side 5xx error. */
    object Server : ErrorKind()

    /**
     * Client-side 4xx error (not 401/403/409).
     * @param serverMessage Server-supplied message to show the user directly.
     */
    data class Client(val serverMessage: String? = null) : ErrorKind()

    /** 401 / 403 — permission denied. */
    object PermissionDenied : ErrorKind()

    /** 409 — optimistic-lock conflict. */
    object Conflict : ErrorKind()

    /** Offline with no cached data available. */
    object Offline : ErrorKind()

    /** Unknown / uncategorized. */
    object Unknown : ErrorKind()
}

/**
 * Typed error-state composable. Resolves copy + icon from [ErrorKind] and
 * delegates rendering to the base [ErrorState] in SharedComponents.kt.
 *
 * Material 3 Expressive tokens only:
 *   - Icon tint: `colorScheme.error`
 *   - Container bg (Conflict / PermissionDenied): `colorScheme.errorContainer`
 *   - Text: `colorScheme.onErrorContainer` for contained, else `onSurfaceVariant`
 *   - Retry: teal `colorScheme.secondary`
 *
 * §66.3 "Never block entire UI; allow cancel where meaningful" — callers should
 * place this inside their content column, not as a full-screen replace.
 *
 * @param kind     The error category driving copy + icon selection.
 * @param onRetry  Retry callback. Pass null for non-retryable errors (e.g. PermissionDenied).
 * @param onConflictReload  Reload callback specific to [ErrorKind.Conflict]; shown as
 *                          a secondary "Reload" action alongside the error message.
 * @param modifier Modifier applied to the outer [Column].
 */
@Composable
fun TypedErrorState(
    kind: ErrorKind,
    onRetry: (() -> Unit)? = null,
    onConflictReload: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current

    val message: String = when (kind) {
        is ErrorKind.Network         -> context.getString(R.string.error_network)
        is ErrorKind.Server          -> context.getString(R.string.error_server)
        is ErrorKind.Client          -> kind.serverMessage
                                        ?: context.getString(R.string.error_unknown)
        is ErrorKind.PermissionDenied -> context.getString(R.string.error_permission_denied)
        is ErrorKind.Conflict        -> context.getString(R.string.error_conflict)
        is ErrorKind.Offline         -> context.getString(R.string.error_offline_cached)
        is ErrorKind.Unknown         -> context.getString(R.string.error_unknown)
    }

    val icon = when (kind) {
        is ErrorKind.Network          -> Icons.Default.CloudOff
        is ErrorKind.Server           -> Icons.Default.Error
        is ErrorKind.Client           -> Icons.Default.ErrorOutline
        is ErrorKind.PermissionDenied -> Icons.Default.Lock
        is ErrorKind.Conflict         -> Icons.Default.SyncProblem
        is ErrorKind.Offline          -> Icons.Default.CloudOff
        is ErrorKind.Unknown          -> Icons.Default.Error
    }

    // Conflict gets a special "Reload" CTA in addition to (or instead of) retry.
    val effectiveRetry: (() -> Unit)? = when {
        kind is ErrorKind.Conflict && onConflictReload != null -> null  // show Reload instead
        kind is ErrorKind.PermissionDenied                     -> null  // not retryable
        else                                                   -> onRetry
    }

    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Icon(
            icon,
            contentDescription = context.getString(R.string.cd_error_icon),
            modifier = Modifier.size(28.dp),
            tint = MaterialTheme.colorScheme.error,
        )
        Text(
            message,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        if (effectiveRetry != null) {
            TextButton(
                onClick = effectiveRetry,
                colors = ButtonDefaults.textButtonColors(
                    contentColor = MaterialTheme.colorScheme.secondary, // teal
                ),
            ) {
                Text(context.getString(R.string.action_retry))
            }
        }
        // Conflict "Reload" action
        if (kind is ErrorKind.Conflict && onConflictReload != null) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (onRetry != null) {
                    TextButton(
                        onClick = onRetry,
                        colors = ButtonDefaults.textButtonColors(
                            contentColor = MaterialTheme.colorScheme.onSurfaceVariant,
                        ),
                    ) {
                        Text(context.getString(R.string.action_retry))
                    }
                }
                TextButton(
                    onClick = onConflictReload,
                    colors = ButtonDefaults.textButtonColors(
                        contentColor = MaterialTheme.colorScheme.secondary,
                    ),
                ) {
                    Text(context.getString(R.string.error_conflict_reload))
                }
            }
        }
    }
}

/**
 * Inline cached-data banner surface.
 *
 * §66.3 "Network errors: cached data still shown where possible + banner."
 *
 * Placed above the list content (below [OfflineBanner] if both are visible).
 * Uses [errorContainer] / [onErrorContainer] to stay on-brand without being
 * alarming (the real offline banner is already shown at top-of-screen).
 *
 * Wave 4 targets: migrate TicketListScreen / CustomerListScreen after
 * [OfflineBanner] is already wired.
 */
@Composable
fun CachedDataBanner(modifier: Modifier = Modifier) {
    val context = LocalContext.current
    Surface(
        modifier = modifier.fillMaxWidth(),
        color = MaterialTheme.colorScheme.errorContainer,
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(
                Icons.Default.CloudOff,
                contentDescription = null, // decorative; sibling Text carries announcement
                tint = MaterialTheme.colorScheme.onErrorContainer,
                modifier = Modifier.size(16.dp),
            )
            Text(
                context.getString(R.string.error_offline_cached),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onErrorContainer,
            )
        }
    }
}
