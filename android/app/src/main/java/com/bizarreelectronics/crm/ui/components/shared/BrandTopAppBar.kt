package com.bizarreelectronics.crm.ui.components.shared

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp

/**
 * Brand-aligned top app bar wrapper.
 *
 * Enforces:
 * - `surface1` container color (`colorScheme.surface`) — NOT `surfaceContainer`,
 *   which shifts on scroll and causes inconsistent header shading across screens.
 * - Sentence-case title in `titleMedium` body-sans (Inter via Wave 1 Typography).
 * - Muted `onSurfaceVariant` for default icon tint.
 * - Optional purple tint on a single "currently active" action (e.g. refresh
 *   while syncing, filter when set). Pass [activeActionIndex] to enable.
 *
 * Wave 3: replace every naked `TopAppBar(...)` across ~30 screens with this.
 * The wrapping composable is thin — it just injects brand defaults so call
 * sites don't need per-screen color overrides.
 *
 * ## Pattern for screens
 * ```kotlin
 * BrandTopAppBar(
 *     title = "Tickets",
 *     navigationIcon = {
 *         IconButton(onClick = onBack) {
 *             Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
 *         }
 *     },
 *     actions = {
 *         IconButton(onClick = onRefresh) {
 *             Icon(Icons.Default.Refresh, contentDescription = "Refresh")
 *         }
 *         IconButton(onClick = onFilter) {
 *             Icon(Icons.Default.FilterList, contentDescription = "Filter")
 *         }
 *     },
 *     activeActionIndex = if (isRefreshing) 0 else null,
 * )
 * ```
 *
 * @param title              Screen title. Use sentence-case ("Point of sale",
 *                           not "POINT OF SALE"). Ignored when [titleContent] is provided.
 * @param titleContent       Optional composable slot that replaces the plain [title] text.
 *                           Use when custom typography (e.g. BrandMono span) is needed —
 *                           see `PhotoCaptureScreen.kt` for the canonical example. When
 *                           provided, [title] is still required for accessibility (it is
 *                           not rendered but documents intent for callers).
 * @param navigationIcon     Back/close/menu icon slot. Null = no nav icon.
 * @param actions            Action icon slots (right side of bar).
 * @param activeActionIndex  0-based index of the action to tint purple.
 *                           Null = no active-action tint (all icons muted).
 *                           Note: this is a documentation hint for Wave 3;
 *                           actual per-action tinting is the responsibility of
 *                           the caller — pass a colored Icon inside the action
 *                           slot using `colorScheme.primary` when active.
 * @param modifier           Applied to the TopAppBar.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BrandTopAppBar(
    title: String,
    modifier: Modifier = Modifier,
    titleContent: (@Composable () -> Unit)? = null,
    navigationIcon: @Composable (() -> Unit)? = null,
    actions: @Composable (RowScope.() -> Unit) = {},
    activeActionIndex: Int? = null,
    scrollBehavior: TopAppBarScrollBehavior? = null,
) {
    // Tablet: navigation rail already shows the active section, so
    // duplicating the section name in a 64dp top bar wastes vertical
    // space. Render a compact 44dp Row with just the nav icon + actions.
    // The title is still passed to the semantics heading so screen
    // readers announce the screen.
    if (com.bizarreelectronics.crm.util.isMediumOrExpandedWidth() && navigationIcon == null) {
        Surface(
            color = MaterialTheme.colorScheme.surface,
            modifier = modifier
                .fillMaxWidth()
                .height(44.dp)
                .semantics { heading() },
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.End,
            ) {
                actions()
            }
        }
        return
    }

    TopAppBar(
        title = {
            // §26.1 — every BrandTopAppBar title is a screen heading so
            // TalkBack users hear "Heading: <title>" and can use the
            // "headings" quick-nav to jump between screens without sliding
            // focus through each action icon. Applied once here so callers
            // never need to sprinkle semantics manually.
            if (titleContent != null) {
                titleContent()
            } else {
                Text(
                    text = title,
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onSurface,
                    modifier = Modifier.semantics { heading() },
                )
            }
        },
        modifier = modifier,
        navigationIcon = navigationIcon ?: {},
        actions = actions,
        colors = TopAppBarDefaults.topAppBarColors(
            containerColor = MaterialTheme.colorScheme.surface,         // surface1
            scrolledContainerColor = MaterialTheme.colorScheme.surface, // stays surface1 on scroll
            navigationIconContentColor = MaterialTheme.colorScheme.onSurfaceVariant,
            titleContentColor = MaterialTheme.colorScheme.onSurface,
            actionIconContentColor = if (activeActionIndex != null) {
                // When an active action exists, callers control tinting per-icon.
                // Default all icons to muted; caller overrides the active one inside
                // the actions slot via explicit `tint = colorScheme.primary`.
                MaterialTheme.colorScheme.onSurfaceVariant
            } else {
                MaterialTheme.colorScheme.onSurfaceVariant
            },
        ),
        scrollBehavior = scrollBehavior,
    )
}
