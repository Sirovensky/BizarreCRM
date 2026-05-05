package com.bizarreelectronics.crm.ui.screens.calls

import android.app.PictureInPictureParams
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.util.Rational
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.lifecycleScope
import com.bizarreelectronics.crm.service.CallNotificationService
import com.bizarreelectronics.crm.ui.theme.BizarreCrmTheme
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * §42.2 — In-call UI screen. Handles:
 * - Outbound call: launched by CallsViewModel after POST /voice/call succeeds.
 * - Inbound call: launched from FCM high-priority data push (CallNotificationService).
 *
 * PiP is supported: user can swipe home and the call persists in a floating
 * mini-window. PiP aspect ratio 9:16 portrait.
 *
 * Audio handling is server-bridged — this Activity displays call state only;
 * no raw RTP processing occurs on the device.
 *
 * TelecomManager / ConnectionService self-managed approach is deferred per
 * §42 constraints; this Activity stubs the call UI.
 */
@AndroidEntryPoint
class CallInProgressActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val callId = intent.getLongExtra(EXTRA_CALL_ID, -1L)
        val callerName = intent.getStringExtra(EXTRA_CALLER_NAME) ?: "Unknown"
        val callerNumber = intent.getStringExtra(EXTRA_CALLER_NUMBER) ?: ""
        val isIncoming = intent.getBooleanExtra(EXTRA_IS_INCOMING, false)

        setContent {
            BizarreCrmTheme {
                CallInProgressScreen(
                    callId = callId,
                    callerName = callerName,
                    callerNumber = callerNumber,
                    isIncoming = isIncoming,
                    onAnswer = { handleAnswer(callId) },
                    onDecline = { handleHangup(callId, answered = false) },
                    onHangup = { handleHangup(callId, answered = true) },
                    onEnterPip = { enterPipMode() },
                )
            }
        }

        // Start foreground call notification
        CallNotificationService.start(this, callId, callerName, callerNumber, isIncoming)
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        enterPipMode()
    }

    override fun onDestroy() {
        super.onDestroy()
        CallNotificationService.stop(this)
    }

    private fun enterPipMode() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val params = PictureInPictureParams.Builder()
                .setAspectRatio(Rational(9, 16))
                .build()
            enterPictureInPictureMode(params)
        }
    }

    private fun handleAnswer(callId: Long) {
        // Server-bridged: fire POST /voice/call/:id/answer if implemented;
        // for now just update local state.
        lifecycleScope.launch {
            // Notify server (404-tolerant)
        }
    }

    private fun handleHangup(callId: Long, answered: Boolean) {
        lifecycleScope.launch {
            // POST /voice/call/:id/hangup — 404 tolerated
            runCatching { /* voiceApi.hangup(callId) */ }
            CallNotificationService.stop(this@CallInProgressActivity)
            finish()
        }
    }

    companion object {
        const val EXTRA_CALL_ID = "extra_call_id"
        const val EXTRA_CALLER_NAME = "extra_caller_name"
        const val EXTRA_CALLER_NUMBER = "extra_caller_number"
        const val EXTRA_IS_INCOMING = "extra_is_incoming"

        fun launch(
            context: Context,
            callId: Long,
            callerName: String,
            callerNumber: String,
            isIncoming: Boolean = false,
        ) {
            val intent = Intent(context, CallInProgressActivity::class.java).apply {
                putExtra(EXTRA_CALL_ID, callId)
                putExtra(EXTRA_CALLER_NAME, callerName)
                putExtra(EXTRA_CALLER_NUMBER, callerNumber)
                putExtra(EXTRA_IS_INCOMING, isIncoming)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            }
            context.startActivity(intent)
        }
    }
}

// ── Compose UI ────────────────────────────────────────────────────────────────

@Composable
fun CallInProgressScreen(
    callId: Long,
    callerName: String,
    callerNumber: String,
    isIncoming: Boolean,
    onAnswer: () -> Unit,
    onDecline: () -> Unit,
    onHangup: () -> Unit,
    onEnterPip: () -> Unit,
) {
    var callAnswered by remember { mutableStateOf(!isIncoming) }
    var elapsedSeconds by remember { mutableStateOf(0) }

    // Count up timer while call is in progress
    LaunchedEffect(callAnswered) {
        if (callAnswered) {
            while (true) {
                delay(1000)
                elapsedSeconds++
            }
        }
    }

    Surface(
        modifier = Modifier.fillMaxSize(),
        color = MaterialTheme.colorScheme.surface,
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.SpaceBetween,
        ) {
            // PiP button
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                IconButton(onClick = onEnterPip) {
                    Icon(Icons.Default.PictureInPicture, contentDescription = "Picture in picture")
                }
            }

            // Caller info
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                // Avatar placeholder
                Surface(
                    modifier = Modifier.size(96.dp),
                    shape = CircleShape,
                    color = MaterialTheme.colorScheme.primaryContainer,
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Text(
                            callerName.firstOrNull()?.uppercase() ?: "?",
                            style = MaterialTheme.typography.headlineLarge,
                            fontWeight = FontWeight.Bold,
                        )
                    }
                }

                Text(callerName, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                Text(callerNumber, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)

                Text(
                    when {
                        isIncoming && !callAnswered -> "Incoming call"
                        callAnswered -> formatTimer(elapsedSeconds)
                        else -> "Calling..."
                    },
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            // Action buttons
            if (isIncoming && !callAnswered) {
                // Incoming: Answer / Decline
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceEvenly,
                ) {
                    CallButton(
                        icon = Icons.Default.CallEnd,
                        label = "Decline",
                        containerColor = MaterialTheme.colorScheme.error,
                        onClick = onDecline,
                    )
                    CallButton(
                        icon = Icons.Default.Call,
                        label = "Answer",
                        containerColor = Color(0xFF2E7D32),
                        onClick = { callAnswered = true; onAnswer() },
                    )
                }
            } else {
                // In-call: Hangup only
                CallButton(
                    icon = Icons.Default.CallEnd,
                    label = "Hang up",
                    containerColor = MaterialTheme.colorScheme.error,
                    onClick = onHangup,
                )
            }
        }
    }
}

@Composable
private fun CallButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    containerColor: Color,
    onClick: () -> Unit,
) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        FloatingActionButton(
            onClick = onClick,
            containerColor = containerColor,
            modifier = Modifier.size(72.dp),
        ) {
            Icon(icon, contentDescription = label, modifier = Modifier.size(32.dp))
        }
        Text(label, style = MaterialTheme.typography.bodySmall)
    }
}

private fun formatTimer(seconds: Int): String {
    val m = seconds / 60
    val s = seconds % 60
    return "%02d:%02d".format(m, s)
}
