package com.bizarreelectronics.crm.ui.components.shared

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.R

// NOTE: The base [LoadingIndicator] (small spinner for in-button / in-toolbar use)
// lives in SharedComponents.kt (same package). This file adds two higher-level
// loading state helpers following §66.2 rules:
//
//   §66.2-a BrandSkeleton ≤ 300ms before real data     → already in SharedComponents.kt
//   §66.2-b CircularProgressIndicator only for unknown-duration actions
//   §66.2-c Prefer determinate bar where % known
//   §66.2-d Never block entire UI; allow cancel where meaningful

/**
 * Centered indeterminate spinner for unknown-duration actions.
 *
 * §66.2: Use only where the duration is truly unknown (e.g. an initial full-screen
 * load with no cached data, a save operation). For list loads, prefer [BrandSkeleton].
 *
 * The [Box] has an accessibility [contentDescription] so TalkBack announces the
 * loading state even though there is no visible text.
 *
 * @param modifier Applied to the outer [Box].
 */
@Composable
fun FullScreenLoading(modifier: Modifier = Modifier) {
    val context = LocalContext.current
    Box(
        modifier = modifier
            .fillMaxWidth()
            .padding(32.dp)
            .semantics { contentDescription = context.getString(R.string.loading_content_description) },
        contentAlignment = Alignment.Center,
    ) {
        CircularProgressIndicator(
            modifier = Modifier.size(36.dp),
            color = MaterialTheme.colorScheme.primary,
            trackColor = MaterialTheme.colorScheme.surfaceVariant,
        )
    }
}

/**
 * Determinate progress bar for operations where a percentage is known.
 *
 * §66.2: Prefer this over [FullScreenLoading] whenever progress (0f–1f) is
 * available — e.g. PDF export, bulk import, backup restore.
 *
 * @param progress  Fraction complete in [0f, 1f].
 * @param label     Accessibility label describing what is loading (e.g. "Importing customers").
 * @param modifier  Applied to the [LinearProgressIndicator].
 */
@Composable
fun DeterminateProgress(
    progress: Float,
    label: String,
    modifier: Modifier = Modifier,
) {
    LinearProgressIndicator(
        progress = { progress.coerceIn(0f, 1f) },
        modifier = modifier
            .fillMaxWidth()
            .semantics { contentDescription = label },
        color = MaterialTheme.colorScheme.primary,
        trackColor = MaterialTheme.colorScheme.surfaceVariant,
    )
}
