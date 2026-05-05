package com.bizarreelectronics.crm.ui.screens.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.ui.auth.PinDots
import com.bizarreelectronics.crm.ui.auth.PinKeypad

/**
 * §2.15 L387-L388 — Self-service forgot-PIN flow.
 *
 * ## Happy path
 *
 * 1. User taps "Forgot PIN?" on [com.bizarreelectronics.crm.ui.auth.PinLockScreen].
 * 2. This screen renders an email input field. User enters email → taps "Send reset link".
 * 3. Server dispatches a link that opens `bizarrecrm://forgot-pin/<token>`.
 * 4. MainActivity publishes the token to [com.bizarreelectronics.crm.util.DeepLinkBus].
 * 5. [ForgotPinViewModel] advances to `SettingPin` — the PIN keypad is shown.
 * 6. User enters a new PIN (validated against PinBlocklist client-side first).
 * 7. On server success, local hash mirror is updated; user is directed back to unlock.
 *
 * ## 404 / email-disabled path
 *
 * When the server returns 404 (email feature absent on self-hosted tenant),
 * [ForgotPinViewModel.UiState.FeatureDisabled] is shown with copy directing the
 * user to ask their manager to reset via the Employees screen.
 *
 * ## Composable reuse
 *
 * PIN entry reuses [PinKeypad] and [PinDots] from the lock-screen package to
 * keep visual consistency.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ForgotPinScreen(
    onBack: () -> Unit,
    onSuccess: () -> Unit,
    viewModel: ForgotPinViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()

    LaunchedEffect(state) {
        if (state is ForgotPinViewModel.UiState.Success) {
            onSuccess()
        }
    }

    Scaffold(
        topBar = {
            CenterAlignedTopAppBar(
                title = { Text("Forgot PIN") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { padding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(horizontal = 24.dp),
            contentAlignment = Alignment.Center,
        ) {
            when (val s = state) {
                is ForgotPinViewModel.UiState.Idle,
                is ForgotPinViewModel.UiState.RequestingEmail,
                is ForgotPinViewModel.UiState.Error -> {
                    val isLoading = s is ForgotPinViewModel.UiState.RequestingEmail
                    val error = (s as? ForgotPinViewModel.UiState.Error)?.message
                    EmailRequestStep(
                        isLoading = isLoading,
                        errorMessage = error,
                        onRequest = viewModel::requestEmailReset,
                    )
                }

                is ForgotPinViewModel.UiState.EmailSent -> {
                    EmailSentStep()
                }

                is ForgotPinViewModel.UiState.SettingPin -> {
                    NewPinStep(
                        entered = s.entered,
                        onDigit = viewModel::onDigit,
                        onBackspace = viewModel::onBackspace,
                    )
                }

                is ForgotPinViewModel.UiState.Success -> {
                    // LaunchedEffect above fires onSuccess — nothing to render here.
                    Box(contentAlignment = Alignment.Center, modifier = Modifier.fillMaxSize()) {
                        CircularProgressIndicator()
                    }
                }

                is ForgotPinViewModel.UiState.FeatureDisabled -> {
                    FeatureDisabledStep(onBack = onBack)
                }
            }
        }
    }
}

// region — step composables

@Composable
private fun EmailRequestStep(
    isLoading: Boolean,
    errorMessage: String?,
    onRequest: (String) -> Unit,
) {
    var email by remember { mutableStateOf("") }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .widthIn(max = 400.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text(
            text = "Reset your PIN",
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.SemiBold,
        )
        Text(
            text = "Enter the email address for your account. We'll send you a link that expires in 15 minutes.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
        OutlinedTextField(
            value = email,
            onValueChange = { email = it },
            label = { Text("Email address") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
            keyboardOptions = KeyboardOptions(
                keyboardType = KeyboardType.Email,
                imeAction = ImeAction.Done,
            ),
            keyboardActions = KeyboardActions(
                onDone = { onRequest(email) },
            ),
            isError = errorMessage != null,
            supportingText = if (errorMessage != null) {
                { Text(errorMessage, color = MaterialTheme.colorScheme.error) }
            } else null,
            enabled = !isLoading,
        )
        if (isLoading) {
            CircularProgressIndicator()
        } else {
            Button(
                onClick = { onRequest(email) },
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text("Send reset link")
            }
        }
    }
}

@Composable
private fun EmailSentStep() {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .widthIn(max = 400.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text(
            text = "Check your email",
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.SemiBold,
        )
        Text(
            text = "We sent a PIN reset link to your email address. Tap the link in the email to continue — it expires in 15 minutes.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(8.dp))
        Text(
            text = "If you don't see the email, check your spam folder or ask your manager to reset your PIN from the Employees screen.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
    }
}

@Composable
private fun NewPinStep(
    entered: String,
    onDigit: (Char, Int) -> Unit,
    onBackspace: () -> Unit,
    pinLength: Int = ForgotPinViewModel.DEFAULT_PIN_LENGTH,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .widthIn(max = 420.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(24.dp),
    ) {
        Text(
            text = "Choose a new PIN",
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.SemiBold,
        )
        Text(
            text = "Enter a new $pinLength-digit PIN. Avoid common sequences like 1234.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
        PinDots(
            entered = entered.length,
            length = pinLength,
            shakeTrigger = 0,
            revealDigits = false,
            enteredDigits = entered,
        )
        PinKeypad(
            enabled = true,
            onDigit = { c -> onDigit(c, pinLength) },
            onBackspace = onBackspace,
            modifier = Modifier.widthIn(max = 320.dp),
        )
    }
}

@Composable
private fun FeatureDisabledStep(onBack: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .widthIn(max = 400.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text(
            text = "PIN reset unavailable",
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.SemiBold,
        )
        Text(
            text = "Email-based PIN reset is not enabled on this server. Ask your manager to reset your PIN from the Employees screen.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(8.dp))
        TextButton(onClick = onBack) {
            Text("Go back")
        }
    }
}

// endregion
