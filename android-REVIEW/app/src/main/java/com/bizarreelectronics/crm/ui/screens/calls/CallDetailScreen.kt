package com.bizarreelectronics.crm.ui.screens.calls

import android.content.Context
import android.content.Intent
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.data.remote.api.CallLogEntry
import com.bizarreelectronics.crm.ui.components.WaveDivider
import com.bizarreelectronics.crm.ui.components.shared.BrandCard
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.util.DateFormatter

/**
 * §42 — Call detail: shows call metadata, recording playback (ExoPlayer), and
 * transcription (server-side stub). Provides "Call back" dial-out intent.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CallDetailScreen(
    callId: Long,
    onBack: () -> Unit,
    viewModel: CallsViewModel = hiltViewModel(),
) {
    val state by viewModel.detailState.collectAsState()
    val context = LocalContext.current

    LaunchedEffect(callId) { viewModel.loadCallDetail(callId) }

    Scaffold(
        topBar = {
            Column {
                BrandTopAppBar(
                    title = "Call Detail",
                    navigationIcon = {
                        IconButton(onClick = onBack) {
                            Icon(Icons.Default.ArrowBack, contentDescription = "Back")
                        }
                    },
                )
                WaveDivider()
            }
        },
    ) { padding ->
        when {
            state.isLoading -> Box(
                modifier = Modifier.fillMaxSize().padding(padding),
                contentAlignment = Alignment.Center,
            ) { CircularProgressIndicator() }

            state.error != null -> Box(
                modifier = Modifier.fillMaxSize().padding(padding),
                contentAlignment = Alignment.Center,
            ) {
                ErrorState(
                    message = state.error ?: "Failed to load call",
                    onRetry = { viewModel.loadCallDetail(callId) },
                )
            }

            state.entry != null -> CallDetailContent(
                entry = state.entry!!,
                transcription = state.transcription,
                transcriptionLoading = state.transcriptionLoading,
                modifier = Modifier.padding(padding),
                onCallBack = { number -> dialNumber(context, number) },
                onLoadTranscription = { viewModel.loadTranscription(callId) },
                onPlayRecording = { url -> playRecording(context, url) },
            )
        }
    }
}

// ── Content ───────────────────────────────────────────────────────────────────

@Composable
private fun CallDetailContent(
    entry: CallLogEntry,
    transcription: String?,
    transcriptionLoading: Boolean,
    modifier: Modifier = Modifier,
    onCallBack: (String) -> Unit,
    onLoadTranscription: () -> Unit,
    onPlayRecording: (String) -> Unit,
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Spacer(modifier = Modifier.height(8.dp))

        // Call info card
        BrandCard(modifier = Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier.fillMaxWidth().padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    val icon = when {
                        entry.direction == "missed" || entry.status == "missed" -> Icons.Default.PhoneMissed
                        entry.direction == "inbound" -> Icons.Default.PhoneCallback
                        else -> Icons.Default.PhoneForwarded
                    }
                    Icon(icon, contentDescription = null, modifier = Modifier.size(32.dp))
                    Spacer(modifier = Modifier.width(12.dp))
                    Column {
                        Text(
                            entry.customer_name ?: entry.from_number,
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.Bold,
                        )
                        Text(
                            entry.from_number,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }

                HorizontalDivider()

                DetailRow(label = "Direction", value = entry.direction.replaceFirstChar { it.uppercase() })
                DetailRow(label = "Status", value = entry.status.replaceFirstChar { it.uppercase() })
                DetailRow(
                    label = "Duration",
                    value = when {
                        entry.duration_seconds < 60 -> "${entry.duration_seconds}s"
                        entry.duration_seconds < 3600 -> "${entry.duration_seconds / 60}m ${entry.duration_seconds % 60}s"
                        else -> "${entry.duration_seconds / 3600}h ${(entry.duration_seconds % 3600) / 60}m"
                    },
                )
                DetailRow(label = "Started", value = DateFormatter.formatRelative(entry.started_at))
                entry.ended_at?.let { DetailRow(label = "Ended", value = DateFormatter.formatRelative(it)) }
            }
        }

        // Call back button
        OutlinedButton(
            onClick = { onCallBack(entry.from_number) },
            modifier = Modifier.fillMaxWidth(),
        ) {
            Icon(Icons.Default.Phone, contentDescription = null, modifier = Modifier.size(18.dp))
            Spacer(modifier = Modifier.width(8.dp))
            Text("Call back ${entry.from_number}")
        }

        // Recording playback
        if (entry.recording_url != null) {
            BrandCard(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.fillMaxWidth().padding(16.dp)) {
                    Text("Recording", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                    Spacer(modifier = Modifier.height(8.dp))
                    Button(
                        onClick = { onPlayRecording(entry.recording_url) },
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Icon(Icons.Default.PlayArrow, contentDescription = null, modifier = Modifier.size(20.dp))
                        Spacer(modifier = Modifier.width(6.dp))
                        Text("Play Recording")
                    }
                }
            }
        }

        // Transcription (server-side stub)
        if (entry.has_transcription || entry.recording_url != null) {
            BrandCard(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.fillMaxWidth().padding(16.dp)) {
                    Text("Transcription", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                    Spacer(modifier = Modifier.height(8.dp))
                    when {
                        transcriptionLoading -> CircularProgressIndicator(modifier = Modifier.size(24.dp))
                        transcription != null -> Text(transcription, style = MaterialTheme.typography.bodySmall)
                        else -> TextButton(onClick = onLoadTranscription) { Text("Load transcription") }
                    }
                }
            }
        }

        Spacer(modifier = Modifier.height(24.dp))
    }
}

@Composable
private fun DetailRow(label: String, value: String) {
    Row(modifier = Modifier.fillMaxWidth()) {
        Text(
            "$label:",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.width(80.dp),
        )
        Text(value, style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.Medium)
    }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

/** §42.1 — Intent.ACTION_DIAL (no CALL_PHONE required). */
private fun dialNumber(context: Context, number: String) {
    context.startActivity(
        Intent(Intent.ACTION_DIAL, android.net.Uri.parse("tel:${number.replace(" ", "")}")),
    )
}

/**
 * Opens the recording URL via an ACTION_VIEW intent.
 * ExoPlayer integration would require a dedicated composable; for now, the
 * system media player handles the playback while ExoPlayer is wired in a
 * follow-up (§42.3).
 */
private fun playRecording(context: Context, url: String) {
    runCatching {
        val intent = Intent(Intent.ACTION_VIEW, android.net.Uri.parse(url)).apply {
            setDataAndType(android.net.Uri.parse(url), "audio/*")
        }
        context.startActivity(intent)
    }
}
