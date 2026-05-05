package com.bizarreelectronics.crm.ui.components

// §2.16 L401 — SensitiveScreenGuard: composable biometric re-auth gate.
//
// Wrap the root Scaffold body of any sensitive screen with this composable.
// On entry it calls SessionTimeout.requireReAuthNow(level) and — if the session
// already requires re-auth — immediately shows a BiometricPrompt. The screen
// content is hidden behind a blocking overlay until the user authenticates.
//
// Sensitivity → SessionTimeout.Level mapping (KDoc below).
//
// Non-blocking contract (line 401):
//   If BiometricAuth.canAuthenticate returns false, or the prompt fails with
//   BiometricFailure.Disabled, the guard treats the user as Verified and logs
//   a warning. The user must re-auth at the next normal timeout interval.

import android.util.Log
import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.fragment.app.FragmentActivity
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import com.bizarreelectronics.crm.ui.auth.BiometricAuth
import com.bizarreelectronics.crm.ui.auth.BiometricFailure
import com.bizarreelectronics.crm.util.SessionTimeout
import com.bizarreelectronics.crm.util.SessionTimeoutCore
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject

// ---------------------------------------------------------------------------
// ViewModel — thin holder that exposes @Singleton dependencies to composables
// ---------------------------------------------------------------------------

/**
 * Thin Hilt ViewModel used as a DI bridge to deliver [SessionTimeout] and
 * [BiometricAuth] singletons into composable scope via [hiltViewModel].
 *
 * No state lives here — all guard state is local `remember` state in
 * [SensitiveScreenGuard].
 */
@HiltViewModel
class SensitiveScreenGuardViewModel @Inject constructor(
    val sessionTimeout: SessionTimeout,
    val biometricAuth: BiometricAuth,
) : ViewModel()

private const val TAG = "SensitiveScreenGuard"

// ---------------------------------------------------------------------------
// Sensitivity enum
// ---------------------------------------------------------------------------

/**
 * Sensitivity tier for a screen that needs biometric re-auth on entry.
 *
 * Maps to [SessionTimeoutCore.ReAuthLevel] as follows:
 *
 * | [Sensitivity]  | [SessionTimeoutCore.ReAuthLevel] | Threshold (default) |
 * |---------------|----------------------------------|---------------------|
 * | [Payment]     | [SessionTimeoutCore.ReAuthLevel.Biometric] (Medium) | 15 min idle |
 * | [Billing]     | [SessionTimeoutCore.ReAuthLevel.Password]  (High)   | 4 hr idle   |
 * | [DangerZone]  | [SessionTimeoutCore.ReAuthLevel.Full]      (Critical)| 30 day idle |
 *
 * The guard always forces an immediate re-auth check on screen entry via
 * [SessionTimeoutCore.requireReAuthNow], regardless of how long the user has
 * been idle.
 */
enum class Sensitivity {
    /** Payment terminal / checkout. Biometric re-auth (Medium level). */
    Payment,

    /** Billing, recovery codes, password change. Password-level re-auth (High). */
    Billing,

    /** Danger zone / destructive irreversible actions. Full re-auth (Critical). */
    DangerZone,
}

/** Maps [Sensitivity] to the corresponding [SessionTimeoutCore.ReAuthLevel]. */
private fun Sensitivity.toReAuthLevel(): SessionTimeoutCore.ReAuthLevel = when (this) {
    Sensitivity.Payment    -> SessionTimeoutCore.ReAuthLevel.Biometric
    Sensitivity.Billing    -> SessionTimeoutCore.ReAuthLevel.Password
    Sensitivity.DangerZone -> SessionTimeoutCore.ReAuthLevel.Full
}

// ---------------------------------------------------------------------------
// Guard state
// ---------------------------------------------------------------------------

private sealed class GuardState {
    /** Waiting to check whether re-auth is required. */
    object Checking : GuardState()

    /** Biometric prompt is being shown. */
    object Prompting : GuardState()

    /** User has authenticated (or biometrics are unavailable — fall-through). */
    object Verified : GuardState()

    /** Prompt failed with a non-Disabled failure; user may retry. */
    object Blocked : GuardState()
}

// ---------------------------------------------------------------------------
// Composable
// ---------------------------------------------------------------------------

/**
 * Wraps [content] behind a biometric re-auth gate.
 *
 * On first composition the guard calls [sessionTimeout.requireReAuthNow] with
 * the [SessionTimeoutCore.ReAuthLevel] that corresponds to [sensitivity].
 * If the session already requires re-auth (or [requireReAuthNow] raises it),
 * a [BiometricPrompt][com.bizarreelectronics.crm.ui.auth.BiometricAuth.showPrompt]
 * is shown immediately.
 *
 * While unverified the composable renders a blocking overlay. On success
 * [sessionTimeout.clear] is called so the inactivity window resets cleanly.
 *
 * **Non-blocking fallback:** if biometrics are unavailable
 * ([BiometricAuth.canAuthenticate] returns false, or the prompt yields
 * [BiometricFailure.Disabled]), the guard logs a warning and treats the user
 * as Verified — content is shown without a prompt. This preserves usability on
 * devices without enrolled biometrics.
 *
 * @param sensitivity  Tier that controls which [SessionTimeoutCore.ReAuthLevel]
 *                     is forced on entry. See [Sensitivity] KDoc for the mapping.
 * @param viewModel    Hilt ViewModel providing [SessionTimeout] and [BiometricAuth]
 *                     singletons. Defaults to [hiltViewModel] so callers need not
 *                     pass it explicitly.
 * @param content      The guarded screen content rendered when [GuardState.Verified].
 */
@Composable
fun SensitiveScreenGuard(
    sensitivity: Sensitivity,
    viewModel: SensitiveScreenGuardViewModel = hiltViewModel(),
    content: @Composable () -> Unit,
) {
    val sessionTimeout = viewModel.sessionTimeout
    val biometricAuth = viewModel.biometricAuth
    val context = LocalContext.current
    val activity = context as? FragmentActivity

    val level = sensitivity.toReAuthLevel()

    var guardState by remember { mutableStateOf<GuardState>(GuardState.Checking) }

    // Helper: attempt biometric prompt or fall through if unavailable.
    fun launchPrompt() {
        if (activity == null) {
            // No FragmentActivity — cannot show BiometricPrompt; fall through.
            Log.w(TAG, "SensitiveScreenGuard: no FragmentActivity, falling through as Verified")
            sessionTimeout.clear()
            guardState = GuardState.Verified
            return
        }
        if (!biometricAuth.canAuthenticate(context)) {
            Log.w(TAG, "SensitiveScreenGuard: biometric unavailable — falling through as Verified")
            Toast.makeText(
                context,
                "Biometric unavailable — sign in again at next timeout.",
                Toast.LENGTH_SHORT,
            ).show()
            sessionTimeout.clear()
            guardState = GuardState.Verified
            return
        }

        guardState = GuardState.Prompting
        biometricAuth.showPrompt(
            activity = activity,
            title = "Verify to continue",
            subtitle = when (sensitivity) {
                Sensitivity.Payment    -> "Confirm your identity to access the payment screen"
                Sensitivity.Billing    -> "Confirm your identity to view billing information"
                Sensitivity.DangerZone -> "Confirm your identity to access sensitive settings"
            },
            onSuccess = {
                sessionTimeout.clear()
                guardState = GuardState.Verified
            },
            onError = { failure ->
                when (failure) {
                    is BiometricFailure.Disabled -> {
                        // Hardware missing / not enrolled — non-blocking fall-through.
                        Log.w(TAG, "SensitiveScreenGuard: BiometricFailure.Disabled — treating as Verified")
                        Toast.makeText(
                            context,
                            "Biometric unavailable — sign in again at next timeout.",
                            Toast.LENGTH_SHORT,
                        ).show()
                        sessionTimeout.clear()
                        guardState = GuardState.Verified
                    }
                    is BiometricFailure.UserCancelled -> {
                        // User dismissed — stay blocked so they can retry.
                        guardState = GuardState.Blocked
                    }
                    is BiometricFailure.SystemError -> {
                        Log.e(TAG, "SensitiveScreenGuard: system error ${failure.code}: ${failure.message}")
                        guardState = GuardState.Blocked
                    }
                }
            },
        )
    }

    // On first composition: force the re-auth level and check whether a prompt is needed.
    LaunchedEffect(Unit) {
        sessionTimeout.requireReAuthNow(level)
        // After requireReAuthNow the state's level will be >= level.
        // Show prompt if the current state requires re-auth.
        val currentLevel = sessionTimeout.state.value.level
        if (currentLevel == SessionTimeoutCore.ReAuthLevel.None) {
            // Session is still valid (requireReAuthNow was called with None — shouldn't
            // happen because we guard against None in requireReAuthNow, but belt-and-
            // suspenders: just verify immediately).
            guardState = GuardState.Verified
        } else {
            launchPrompt()
        }
    }

    // Render
    when (val gs = guardState) {
        is GuardState.Verified -> {
            content()
        }

        is GuardState.Checking, is GuardState.Prompting -> {
            // Show spinner overlay while awaiting the prompt result.
            SensitiveScreenBlockingOverlay(
                message = "Waiting for verification…",
                showRetry = false,
                onRetry = {},
            )
        }

        is GuardState.Blocked -> {
            SensitiveScreenBlockingOverlay(
                message = "Verify to continue",
                showRetry = true,
                onRetry = { launchPrompt() },
            )
        }
    }
}

// ---------------------------------------------------------------------------
// Blocking overlay
// ---------------------------------------------------------------------------

/**
 * Full-screen blocking overlay shown when the guard is unverified.
 * Renders a lock icon, a message, and an optional "Verify" retry button.
 */
@Composable
private fun SensitiveScreenBlockingOverlay(
    message: String,
    showRetry: Boolean,
    onRetry: () -> Unit,
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .semantics { contentDescription = "Verification required. $message" },
        contentAlignment = Alignment.Center,
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
            modifier = Modifier.padding(horizontal = 32.dp),
        ) {
            Icon(
                imageVector = Icons.Default.Lock,
                contentDescription = null,
                modifier = Modifier.size(56.dp),
                tint = MaterialTheme.colorScheme.primary,
            )

            Spacer(Modifier.height(24.dp))

            Text(
                text = message,
                style = MaterialTheme.typography.titleMedium,
                textAlign = TextAlign.Center,
                color = MaterialTheme.colorScheme.onBackground,
            )

            if (!showRetry) {
                Spacer(Modifier.height(24.dp))
                CircularProgressIndicator(modifier = Modifier.size(32.dp))
            }

            if (showRetry) {
                Spacer(Modifier.height(24.dp))
                Button(onClick = onRetry) {
                    Text("Verify")
                }
            }
        }
    }
}
