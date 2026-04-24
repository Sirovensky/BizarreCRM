package com.bizarreelectronics.crm.ui.screens.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Card
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bizarreelectronics.crm.util.RateLimiter
import com.bizarreelectronics.crm.util.RateLimiterCore
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Settings → Rate limit buckets diagnostic screen.
 *
 * Shows a live view of all token-bucket states emitted by [RateLimiter.buckets]
 * and the current queue depth from [RateLimiter.queueState].
 *
 * **Debug-only gate** — this composable is only reachable from [SettingsScreen]
 * when `BuildConfig.DEBUG` is true. Production builds never navigate here because
 * [SettingsScreen] guards the row behind that flag.
 *
 * Read-only: no mutation buttons. The view refreshes automatically as the
 * StateFlow emits new snapshots; no manual refresh is needed.
 *
 * [plan:L258] — ActionPlan §1.2 line 258.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RateLimitBucketsScreen(
    onBack: () -> Unit,
    viewModel: RateLimitBucketsViewModel = hiltViewModel(),
) {
    val rateLimiter = viewModel.rateLimiter
    val buckets by rateLimiter.buckets.collectAsStateWithLifecycle()
    val queueState by rateLimiter.queueState.collectAsStateWithLifecycle()

    Scaffold(
        topBar = {
            CenterAlignedTopAppBar(
                title = { Text("Rate limit buckets") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            item { Spacer(Modifier.height(4.dp)) }

            // Queue-depth summary card
            item {
                Card(modifier = Modifier.fillMaxWidth()) {
                    Column(
                        modifier = Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        Text("Queue depth", style = MaterialTheme.typography.titleSmall)
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                        ) {
                            Text(
                                "Suspended callers",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            Text(
                                queueState.depth.toString(),
                                style = MaterialTheme.typography.bodyMedium,
                            )
                        }
                        if (queueState.slowDownBannerActive) {
                            Text(
                                "SLOW DOWN banner active (depth > ${RateLimiterCore.SLOW_DOWN_QUEUE_DEPTH})",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.error,
                            )
                        }
                    }
                }
            }

            // One card per category bucket
            val sortedEntries = buckets.entries.sortedBy { it.key.name }
            items(sortedEntries, key = { it.key.name }) { (category, bucket) ->
                BucketCard(category = category, bucket = bucket)
            }

            item { Spacer(Modifier.height(8.dp)) }
        }
    }
}

@Composable
private fun BucketCard(
    category: RateLimiterCore.Category,
    bucket: RateLimiterCore.BucketState,
) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(category.name, style = MaterialTheme.typography.titleSmall)

            HorizontalDivider(
                color = MaterialTheme.colorScheme.outline.copy(alpha = 0.3f),
                thickness = 1.dp,
            )

            // Token progress bar
            val fraction = bucket.tokens.toFloat() / bucket.capacity.toFloat()
            LinearProgressIndicator(
                progress = { fraction },
                modifier = Modifier.fillMaxWidth(),
                color = when {
                    fraction > 0.5f -> MaterialTheme.colorScheme.primary
                    fraction > 0.2f -> MaterialTheme.colorScheme.tertiary
                    else -> MaterialTheme.colorScheme.error
                },
                trackColor = MaterialTheme.colorScheme.outline.copy(alpha = 0.2f),
            )

            BucketInfoRow(label = "Tokens available", value = "${bucket.tokens} / ${bucket.capacity}")

            val pauseText = bucket.pausedUntilMs?.let { pausedUntil ->
                val remaining = (pausedUntil - System.currentTimeMillis()).coerceAtLeast(0L)
                if (remaining > 0L) {
                    val sdf = SimpleDateFormat("HH:mm:ss", Locale.US)
                    "Paused until ${sdf.format(Date(pausedUntil))} (${remaining / 1000}s remaining)"
                } else {
                    "Pause expired"
                }
            } ?: "Not paused"
            BucketInfoRow(label = "Server pause", value = pauseText)
        }
    }
}

@Composable
private fun BucketInfoRow(label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(
            label,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(value, style = MaterialTheme.typography.bodySmall)
    }
}
