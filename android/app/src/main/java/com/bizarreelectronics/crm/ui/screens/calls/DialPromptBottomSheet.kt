package com.bizarreelectronics.crm.ui.screens.calls

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.R

/**
 * §42.5 — Click-to-call dial prompt bottom sheet.
 *
 * Shown when the user taps a customer chip / phone number anywhere in the app.
 * Pre-fills the number and customer name if provided.
 *
 * Behaviour:
 *  1. If the tenant has VoIP configured (POST /voice/call returns 200),
 *     the call is initiated as a VoIP call and CallInProgressActivity is launched.
 *  2. If VoIP is not configured (404), falls back to system ACTION_DIAL.
 *  3. Recent outbound numbers are fetched from CallsViewModel (populated on
 *     loadCalls()) and shown as quick-dial chips.
 *
 * Usage:
 * ```kotlin
 * if (state.showDialPrompt) {
 *     DialPromptBottomSheet(
 *         number = state.dialPromptNumber,
 *         customerName = state.dialPromptCustomerName,
 *         customerId = state.dialPromptCustomerId,
 *     )
 * }
 * ```
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DialPromptBottomSheet(
    number: String,
    customerName: String?,
    customerId: Long?,
    recentNumbers: List<String>,
    isInitiating: Boolean,
    viewModel: CallsViewModel = hiltViewModel(),
) {
    val context = LocalContext.current
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    ModalBottomSheet(
        onDismissRequest = viewModel::dismissDialPrompt,
        sheetState = sheetState,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 24.dp)
                .navigationBarsPadding(),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            // Header
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    Icons.Default.Phone,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(24.dp),
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    if (customerName != null)
                        stringResource(R.string.dial_prompt_title_customer, customerName)
                    else
                        stringResource(R.string.dial_prompt_title),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                )
            }

            // Number input
            var editableNumber by remember { mutableStateOf(number) }
            OutlinedTextField(
                value = editableNumber,
                onValueChange = { editableNumber = it; viewModel.updateDialPromptNumber(it) },
                label = { Text(stringResource(R.string.dial_prompt_number_label)) },
                leadingIcon = {
                    Icon(
                        Icons.Default.Phone,
                        contentDescription = null,
                    )
                },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )

            // Recent numbers
            if (recentNumbers.isNotEmpty()) {
                Text(
                    stringResource(R.string.dial_prompt_recent),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                LazyColumn(
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                    modifier = Modifier.heightIn(max = 160.dp),
                ) {
                    items(recentNumbers) { recent ->
                        ListItem(
                            headlineContent = { Text(recent) },
                            leadingContent = {
                                Icon(
                                    Icons.Default.History,
                                    contentDescription = stringResource(
                                        R.string.dial_prompt_recent_cd, recent,
                                    ),
                                )
                            },
                            modifier = Modifier.clickable { editableNumber = recent },
                        )
                    }
                }
            }

            // Action buttons
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                OutlinedButton(
                    onClick = viewModel::dismissDialPrompt,
                    modifier = Modifier.weight(1f),
                ) {
                    Text(stringResource(R.string.action_cancel))
                }
                Button(
                    onClick = {
                        val dialNumber = editableNumber.trim()
                        if (dialNumber.isNotBlank()) {
                            viewModel.initiateVoipCall(
                                number = dialNumber,
                                customerId = customerId,
                                onLaunchCallActivity = { callId, callerName, num ->
                                    CallInProgressActivity.launch(
                                        context = context,
                                        callId = callId,
                                        callerName = callerName,
                                        callerNumber = num,
                                        isIncoming = false,
                                    )
                                },
                                onFallbackDial = { num ->
                                    dialViaSystem(context, num)
                                },
                            )
                        }
                    },
                    enabled = !isInitiating && editableNumber.isNotBlank(),
                    modifier = Modifier
                        .weight(2f)
                        .semantics {
                            contentDescription = "Call ${editableNumber.ifBlank { "number" }}"
                        },
                ) {
                    if (isInitiating) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(18.dp),
                            strokeWidth = 2.dp,
                        )
                    } else {
                        Icon(
                            Icons.Default.Call,
                            contentDescription = null,
                            modifier = Modifier.size(18.dp),
                        )
                        Spacer(modifier = Modifier.width(6.dp))
                        Text(stringResource(R.string.dial_prompt_call_action))
                    }
                }
            }

            Spacer(modifier = Modifier.height(8.dp))
        }
    }
}

// ── Helper ────────────────────────────────────────────────────────────────────

/** §42.1 — Falls back to ACTION_DIAL; no CALL_PHONE permission required. */
private fun dialViaSystem(context: Context, number: String) {
    val normalised = number.replace("[^+\\d]".toRegex(), "")
    context.startActivity(Intent(Intent.ACTION_DIAL, Uri.parse("tel:$normalised")))
}
