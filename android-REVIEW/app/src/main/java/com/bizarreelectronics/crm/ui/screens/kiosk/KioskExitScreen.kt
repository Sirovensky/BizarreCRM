package com.bizarreelectronics.crm.ui.screens.kiosk

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.R
import com.bizarreelectronics.crm.ui.auth.PinDots
import com.bizarreelectronics.crm.ui.auth.PinKeypad
import com.bizarreelectronics.crm.util.rememberReduceMotion

/**
 * §57.5 Manager-PIN exit gate.
 *
 * Shown when a staff member taps "Exit kiosk" from the check-in or signature
 * screen.  Validates against the device PIN stored in [PinPreferences].  On
 * success, [onExitAuthorised] is called — the caller is responsible for invoking
 * [KioskController.exitLockTask] and navigating away.
 *
 * The Back button navigates to [onBack] (returns to the kiosk flow rather than
 * the normal app — prevents customer from escaping via hardware back).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun KioskExitScreen(
    onExitAuthorised: () -> Unit,
    onBack: () -> Unit,
    viewModel: KioskViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsState()
    // §26.4 — honour Reduce Motion for the PinDots shake animation.
    val reduceMotion = rememberReduceMotion(viewModel.appPreferences)

    LaunchedEffect(state.exitAuthorised) {
        if (state.exitAuthorised) {
            onExitAuthorised()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        stringResource(R.string.kiosk_exit_title),
                        style = MaterialTheme.typography.titleLarge,
                    )
                },
                navigationIcon = {
                    IconButton(
                        onClick = onBack,
                        modifier = Modifier.semantics {
                            contentDescription = "Cancel exit — return to kiosk"
                        },
                    ) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = null,
                        )
                    }
                },
            )
        },
    ) { paddingValues ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues),
            contentAlignment = Alignment.Center,
        ) {
            Column(
                modifier = Modifier
                    .widthIn(max = 420.dp)
                    .fillMaxWidth()
                    .padding(horizontal = 32.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(24.dp, Alignment.CenterVertically),
            ) {
                Text(
                    stringResource(R.string.kiosk_exit_headline),
                    style = MaterialTheme.typography.headlineMedium,
                    textAlign = TextAlign.Center,
                )
                Text(
                    stringResource(R.string.kiosk_exit_subhead),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                )

                PinDots(
                    entered = state.exitPinEntered.length,
                    length = 4,
                    shakeTrigger = state.exitPinWrongShakes,
                    revealDigits = false,
                    enteredDigits = state.exitPinEntered,
                    // §26.4: reduceMotion=true swaps shake for a static error border.
                    reduceMotion = reduceMotion,
                )

                state.exitPinError?.let { errMsg ->
                    Text(
                        errMsg,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }

                PinKeypad(
                    enabled = true,
                    onDigit = viewModel::onExitPinDigit,
                    onBackspace = viewModel::onExitPinBackspace,
                    modifier = Modifier.widthIn(max = 320.dp),
                )
            }
        }
    }
}
