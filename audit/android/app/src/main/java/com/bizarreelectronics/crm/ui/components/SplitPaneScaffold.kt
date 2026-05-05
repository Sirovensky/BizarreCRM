package com.bizarreelectronics.crm.ui.components

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.Spacer
import androidx.compose.material3.VerticalDivider
import androidx.compose.ui.platform.LocalConfiguration

/**
 * Tablet / foldable split view. On devices with a viewport >= 600dp wide we
 * render [list] on the left pane and [detail] on the right pane. Below that
 * width we fall back to whichever pane is "active", which lets the same
 * composable power both phones and tablets without duplicating navigation.
 *
 * The width threshold follows Material 3's medium-width breakpoint. We use
 * a raw Row instead of TwoPane because the androidx.window library isn't
 * currently in the dependency graph — adding it is fine if we later need
 * hinge-aware splits on foldables, but the simple threshold is good enough
 * for the 80% case.
 *
 * Usage:
 *     SplitPaneScaffold(
 *         hasSelection = selectedCustomer != null,
 *         list = { CustomerList(onSelect = ::select) },
 *         detail = { selectedCustomer?.let { CustomerDetail(it) } },
 *     )
 */
@Composable
fun SplitPaneScaffold(
    hasSelection: Boolean,
    list: @Composable () -> Unit,
    detail: @Composable () -> Unit,
    modifier: Modifier = Modifier,
    splitThresholdDp: Int = 600,
) {
    val configuration = LocalConfiguration.current
    val isWide = configuration.screenWidthDp >= splitThresholdDp

    if (isWide) {
        Row(modifier = modifier.fillMaxSize()) {
            Box(
                modifier = Modifier
                    .weight(0.4f)
                    .fillMaxSize(),
            ) {
                list()
            }
            VerticalDivider()
            Box(
                modifier = Modifier
                    .weight(0.6f)
                    .fillMaxSize(),
            ) {
                if (hasSelection) {
                    detail()
                } else {
                    SplitPanePlaceholder()
                }
            }
        }
    } else {
        // Phone-sized: render one pane at a time. Caller is expected to
        // handle the back-stack (tap list row → push detail).
        Box(modifier = modifier.fillMaxSize()) {
            if (hasSelection) detail() else list()
        }
    }
}

/**
 * Empty state for the detail pane on tablets when nothing is selected.
 * Kept private because it is a pure implementation detail of the scaffold.
 */
@Composable
private fun SplitPanePlaceholder() {
    Surface(
        modifier = Modifier.fillMaxSize(),
        color = MaterialTheme.colorScheme.surfaceVariant,
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(32.dp),
            verticalArrangement = androidx.compose.foundation.layout.Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                "Select an item to see details",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
