package com.bizarreelectronics.crm.ui.screens.kiosk

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.R
import kotlinx.coroutines.delay

/**
 * §57.2 Kiosk done screen — shown after the customer completes check-in.
 *
 * Auto-returns to [onReturnToStart] after [AUTO_RESET_MS] ms so the kiosk is
 * ready for the next customer without staff intervention.
 */
@Composable
fun KioskDoneScreen(
    customerName: String,
    onReturnToStart: () -> Unit,
) {
    LaunchedEffect(Unit) {
        delay(AUTO_RESET_MS)
        onReturnToStart()
    }

    Scaffold { paddingValues ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues),
            contentAlignment = Alignment.Center,
        ) {
            Column(
                modifier = Modifier
                    .widthIn(max = 480.dp)
                    .fillMaxWidth()
                    .padding(horizontal = 32.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(20.dp, Alignment.CenterVertically),
            ) {
                Icon(
                    Icons.Default.CheckCircle,
                    contentDescription = stringResource(R.string.kiosk_done_icon_cd),
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(72.dp),
                )
                Text(
                    stringResource(R.string.kiosk_done_headline),
                    style = MaterialTheme.typography.headlineMedium,
                    textAlign = TextAlign.Center,
                )
                if (customerName.isNotBlank()) {
                    Text(
                        stringResource(R.string.kiosk_done_subhead, customerName),
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center,
                    )
                }
                Text(
                    stringResource(R.string.kiosk_done_returning),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                )
                FilledTonalButton(
                    onClick = onReturnToStart,
                    modifier = Modifier
                        .fillMaxWidth()
                        .semantics { contentDescription = "Return to kiosk start now" },
                ) {
                    Text(stringResource(R.string.kiosk_done_start_over_cta))
                }
            }
        }
    }
}

private const val AUTO_RESET_MS = 8_000L
