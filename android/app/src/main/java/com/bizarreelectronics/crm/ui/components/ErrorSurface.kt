package com.bizarreelectronics.crm.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Storage
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material.icons.filled.WifiOff
import androidx.compose.material.icons.outlined.CloudOff
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.SearchOff
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.util.AppError
import com.bizarreelectronics.crm.util.ErrorRecovery

/**
 * Reusable error surface driven by [ErrorRecovery.recover] (ActionPlan §1 L230).
 *
 * Feature screens receive an [AppError] from a ViewModel StateFlow. They invoke:
 *
 *   ErrorSurface(
 *       error = state.error ?: return,
 *       onAction = { action -> viewModel.handle(action) },
 *   )
 *
 * The surface displays title, message, and one Button per suggested
 * [ErrorRecovery.Action]. Primary button is the first non-Dismiss action;
 * Dismiss is rendered as a TextButton. Destructive recoveries (rare) render
 * the primary button with errorContainer/onError tint.
 *
 * Icon maps from the AppError branch (WifiOff for Network, Lock for Auth,
 * CloudOff for Server, etc.). Bullets render for Validation with
 * fieldErrorsAsBullets.
 *
 * Composable is self-contained — no ViewModel required. Callers map the
 * emitted [ErrorRecovery.Action] to their own logic (retry submit, navigate
 * to settings, intent to mail support, dismiss the dialog, etc.).
 *
 * @param error     The error to display. When the error is [AppError.Cancelled]
 *                  the composable renders nothing (returns early).
 * @param onAction  Called with the [ErrorRecovery.Action] the user tapped.
 *                  The caller is responsible for routing each action.
 * @param modifier  Applied to the outermost layout container.
 * @param compact   When `true` renders as a small [Surface] card
 *                  (icon + title + message + first action).
 *                  When `false` renders as a centered [Column] with a larger
 *                  icon, titleLarge heading, bodyMedium message, and a
 *                  horizontal actions row.
 */
@Composable
fun ErrorSurface(
    error: AppError,
    onAction: (ErrorRecovery.Action) -> Unit,
    modifier: Modifier = Modifier,
    compact: Boolean = false,
) {
    val recovery = remember(error) { ErrorRecovery.recover(error) }

    // Cancelled branch — stay silent.
    if (recovery.actions.isEmpty()) return

    val icon = iconForError(error)
    val announceText = "${recovery.title}. ${recovery.message}" // TODO(i18n)

    if (compact) {
        CompactErrorSurface(
            recovery = recovery,
            icon = icon,
            announceText = announceText,
            onAction = onAction,
            modifier = modifier,
        )
    } else {
        FullErrorSurface(
            recovery = recovery,
            icon = icon,
            announceText = announceText,
            onAction = onAction,
            modifier = modifier,
        )
    }
}

// ---------------------------------------------------------------------------
// Internal layouts
// ---------------------------------------------------------------------------

@Composable
private fun CompactErrorSurface(
    recovery: ErrorRecovery.Recovery,
    icon: ImageVector,
    announceText: String,
    onAction: (ErrorRecovery.Action) -> Unit,
    modifier: Modifier = Modifier,
) {
    Surface(
        shape = MaterialTheme.shapes.medium,
        color = MaterialTheme.colorScheme.errorContainer,
        modifier = modifier
            .fillMaxWidth()
            .semantics(mergeDescendants = true) {
                liveRegion = LiveRegionMode.Polite
                contentDescription = announceText
            },
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null, // merged into parent semantics
                tint = MaterialTheme.colorScheme.onErrorContainer,
                modifier = Modifier.size(20.dp),
            )

            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = recovery.title,
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.onErrorContainer,
                )
                if (recovery.message.isNotBlank()) {
                    Text(
                        text = recovery.message,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onErrorContainer,
                    )
                }
            }

            // Compact: show only the first non-Dismiss action (or Dismiss fallback).
            val primaryAction = recovery.actions.firstOrNull { it != ErrorRecovery.Action.Dismiss }
                ?: recovery.actions.first()
            val label = actionLabel(primaryAction)
            Button(
                onClick = { onAction(primaryAction) },
                colors = if (recovery.destructive) {
                    ButtonDefaults.buttonColors(
                        containerColor = MaterialTheme.colorScheme.error,
                        contentColor = MaterialTheme.colorScheme.onError,
                    )
                } else {
                    ButtonDefaults.buttonColors()
                },
                modifier = Modifier.semantics {
                    role = Role.Button
                    contentDescription = label
                },
            ) {
                Text(text = label)
            }
        }
    }
}

@Composable
private fun FullErrorSurface(
    recovery: ErrorRecovery.Recovery,
    icon: ImageVector,
    announceText: String,
    onAction: (ErrorRecovery.Action) -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(24.dp)
            .semantics(mergeDescendants = true) {
                liveRegion = LiveRegionMode.Polite
                contentDescription = announceText
            },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null, // merged into parent semantics
            tint = MaterialTheme.colorScheme.error,
            modifier = Modifier.size(48.dp),
        )

        Spacer(modifier = Modifier.height(16.dp))

        Text(
            text = recovery.title,
            style = MaterialTheme.typography.titleLarge,
            color = MaterialTheme.colorScheme.onSurface,
        )

        if (recovery.message.isNotBlank()) {
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = recovery.message,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        Spacer(modifier = Modifier.height(24.dp))

        val primaryAction = recovery.actions.firstOrNull { it != ErrorRecovery.Action.Dismiss }
        val secondaryActions = recovery.actions.filter {
            it != ErrorRecovery.Action.Dismiss && it != primaryAction
        }
        val hasDismiss = ErrorRecovery.Action.Dismiss in recovery.actions

        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (primaryAction != null) {
                val label = actionLabel(primaryAction)
                Button(
                    onClick = { onAction(primaryAction) },
                    colors = if (recovery.destructive) {
                        ButtonDefaults.buttonColors(
                            containerColor = MaterialTheme.colorScheme.errorContainer,
                            contentColor = MaterialTheme.colorScheme.onErrorContainer,
                        )
                    } else {
                        ButtonDefaults.buttonColors()
                    },
                    modifier = Modifier.semantics {
                        role = Role.Button
                        contentDescription = label
                    },
                ) {
                    Text(text = label)
                }
            }

            secondaryActions.forEach { action ->
                val label = actionLabel(action)
                OutlinedButton(
                    onClick = { onAction(action) },
                    modifier = Modifier.semantics {
                        role = Role.Button
                        contentDescription = label
                    },
                ) {
                    Text(text = label)
                }
            }

            if (hasDismiss) {
                val label = actionLabel(ErrorRecovery.Action.Dismiss)
                TextButton(
                    onClick = { onAction(ErrorRecovery.Action.Dismiss) },
                    modifier = Modifier.semantics {
                        role = Role.Button
                        contentDescription = label
                    },
                ) {
                    Text(text = label)
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Pure helpers — internal visibility enables direct JVM unit testing.
// ---------------------------------------------------------------------------

/**
 * Maps an [ErrorRecovery.Action] to its visible button label.
 * // TODO(i18n) — replace with string resource IDs.
 */
internal fun actionLabel(action: ErrorRecovery.Action): String = when (action) {
    ErrorRecovery.Action.Retry -> "Retry" // TODO(i18n)
    ErrorRecovery.Action.EnableNetwork -> "Enable network" // TODO(i18n)
    ErrorRecovery.Action.ReLogin -> "Sign in again" // TODO(i18n)
    ErrorRecovery.Action.OpenSettings -> "Open settings" // TODO(i18n)
    ErrorRecovery.Action.ContactSupport -> "Contact support" // TODO(i18n)
    ErrorRecovery.Action.Dismiss -> "Dismiss" // TODO(i18n)
    ErrorRecovery.Action.FreeStorage -> "Free up space" // TODO(i18n)
    ErrorRecovery.Action.AdjustTime -> "Adjust date & time" // TODO(i18n)
}

/**
 * Maps an [AppError] subtype to an appropriate [ImageVector].
 * Falls back to [Icons.Default.Error] for unrecognised branches.
 */
internal fun iconForError(error: AppError): ImageVector = when (error) {
    is AppError.Network -> Icons.Default.WifiOff
    is AppError.Server -> Icons.Outlined.CloudOff
    is AppError.Auth -> Icons.Default.Lock
    is AppError.Validation -> Icons.Outlined.ErrorOutline
    is AppError.NotFound -> Icons.Outlined.SearchOff
    is AppError.Conflict -> Icons.Default.Sync
    is AppError.Storage -> Icons.Default.Storage
    is AppError.Hardware -> Icons.Default.Build
    AppError.Cancelled -> Icons.Default.Error // never rendered (early return)
    is AppError.Unknown -> Icons.Default.Error
}

/**
 * Selects [ButtonColors] for the primary action button.
 * Exposed as a pure helper so tests can assert the color choice
 * without spinning up a Compose environment.
 *
 * **Note:** The returned [ButtonColors] uses Material3 defaults — in tests
 * this resolves to placeholder colours because there is no real [MaterialTheme].
 * Tests should only call this to verify *which* branch is taken, not the
 * exact colour value.
 *
 * @param destructive   When `true` returns error-tinted colours.
 */
@Composable
internal fun primaryButtonColors(destructive: Boolean) = if (destructive) {
    ButtonDefaults.buttonColors(
        containerColor = MaterialTheme.colorScheme.errorContainer,
        contentColor = MaterialTheme.colorScheme.onErrorContainer,
    )
} else {
    ButtonDefaults.buttonColors()
}
