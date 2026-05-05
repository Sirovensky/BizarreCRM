package com.bizarreelectronics.crm.ui.screens.selfbooking

import android.content.Intent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.R
import kotlinx.coroutines.launch

// ---------------------------------------------------------------------------
// §58.3 — Settings → Online Booking
//
// Route: `settings/online-booking/{locationId}`
// Label: R.string.screen_online_booking_settings
//
// Generates the shareable public booking link for the given location.
// The booking URL is composed client-side from the known server base domain
// and the locationId — no additional server endpoint required for link generation.
//
// Deferred (server endpoints not yet deployed):
//   - Toggle booking enabled/disabled per location
//     <!-- NOTE-defer: requires PUT /api/v1/settings/booking/:locationId endpoint -->
//   - Working hours, buffer times, services-bookable configuration
//     <!-- NOTE-defer: same settings endpoint as above -->
// ---------------------------------------------------------------------------

/**
 * Settings screen for Online Booking link generation and QR sharing.
 *
 * Route: `settings/online-booking/{locationId}`
 * Label: [R.string.screen_online_booking_settings]
 *
 * Allows staff to copy or share the public booking URL for a specific location.
 * Enable/disable per-location and working-hours toggles are deferred until the
 * server settings endpoint is deployed.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun OnlineBookingSettingsScreen(
    locationId: String,
    serverBaseUrl: String = "https://app.bizarrecrm.com",
    onBack: () -> Unit,
) {
    val bookingUrl = "$serverBaseUrl/book/$locationId"
    val context = LocalContext.current
    val clipboard = LocalClipboardManager.current
    val snackbarHostState = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()
    val copiedMessage = stringResource(R.string.self_booking_link_copied)

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = stringResource(R.string.screen_online_booking_settings),
                        style = MaterialTheme.typography.titleMedium,
                    )
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.cd_navigate_back),
                        )
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface,
                    titleContentColor = MaterialTheme.colorScheme.onSurface,
                    navigationIconContentColor = MaterialTheme.colorScheme.onSurfaceVariant,
                ),
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp, vertical = 16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text(
                text = stringResource(R.string.online_booking_link_section_heading),
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.onSurface,
                modifier = Modifier.semantics { heading() },
            )

            OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                ListItem(
                    headlineContent = {
                        Text(
                            text = bookingUrl,
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.Medium,
                        )
                    },
                    supportingContent = {
                        Text(
                            text = stringResource(R.string.online_booking_link_subtitle),
                            style = MaterialTheme.typography.bodySmall,
                        )
                    },
                    leadingContent = {
                        Icon(
                            imageVector = Icons.Default.Link,
                            contentDescription = stringResource(R.string.cd_booking_link_icon),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.size(20.dp),
                        )
                    },
                )
            }

            FilledTonalButton(
                onClick = {
                    clipboard.setText(AnnotatedString(bookingUrl))
                    scope.launch {
                        snackbarHostState.showSnackbar(copiedMessage)
                    }
                },
                modifier = Modifier.fillMaxWidth(),
            ) {
                Icon(
                    imageVector = Icons.Default.ContentCopy,
                    contentDescription = null, // decorative; button label announces action
                    modifier = Modifier
                        .size(18.dp)
                        .padding(end = 4.dp),
                )
                Text(stringResource(R.string.online_booking_copy_link_btn))
            }

            FilledTonalButton(
                onClick = {
                    val shareIntent = Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_TEXT, bookingUrl)
                        putExtra(
                            Intent.EXTRA_SUBJECT,
                            context.getString(R.string.online_booking_share_subject),
                        )
                    }
                    context.startActivity(
                        Intent.createChooser(
                            shareIntent,
                            context.getString(R.string.online_booking_share_chooser_title),
                        )
                    )
                },
                modifier = Modifier.fillMaxWidth(),
            ) {
                Icon(
                    imageVector = Icons.Default.Share,
                    contentDescription = null, // decorative; button label announces action
                    modifier = Modifier
                        .size(18.dp)
                        .padding(end = 4.dp),
                )
                Text(stringResource(R.string.online_booking_share_link_btn))
            }

            // Deferred: enable/disable toggle and working-hours / buffer config.
            // <!-- NOTE-defer: requires PUT /api/v1/settings/booking/:locationId; show placeholder -->
            OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                ListItem(
                    headlineContent = {
                        Text(
                            text = stringResource(R.string.online_booking_advanced_unavailable_title),
                            style = MaterialTheme.typography.bodyMedium,
                        )
                    },
                    supportingContent = {
                        Text(
                            text = stringResource(R.string.online_booking_advanced_unavailable_subtitle),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    },
                )
            }
        }
    }
}
