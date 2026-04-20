package com.bizarreelectronics.crm.ui.components.shared

import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector

/**
 * Brand FAB thin wrapper.
 *
 * Primary FAB = purple via `colorScheme.primary` (theme default).
 * DashboardFab.kt is a bespoke one-off — Wave 3 Dashboard agent handles it
 * separately. This wrapper is for all other screens adding a single FAB.
 *
 * @param onClick   FAB tap callback.
 * @param icon      Icon vector.
 * @param contentDescription Accessibility label for the icon.
 * @param modifier  Applied to the FAB.
 */
@Composable
fun BrandFab(
    onClick: () -> Unit,
    icon: ImageVector,
    contentDescription: String,
    modifier: Modifier = Modifier,
) {
    FloatingActionButton(
        onClick = onClick,
        modifier = modifier,
        // containerColor defaults to primaryContainer via theme (purple tint).
        // For a fully-filled purple FAB, override: containerColor = colorScheme.primary
        containerColor = MaterialTheme.colorScheme.primary,
        contentColor = MaterialTheme.colorScheme.onPrimary,
    ) {
        Icon(icon, contentDescription = contentDescription)
    }
}

/**
 * Brand bottom sheet wrapper.
 *
 * Uses `surface2` (surfaceContainerHigh) as the sheet container color,
 * consistent with the dialog surface treatment.
 *
 * Wave 3: use this for any `ModalBottomSheet` that currently relies on the
 * default `surfaceContainer` color (which may be lighter or different shade).
 *
 * @param onDismissRequest Called when the sheet is dismissed.
 * @param sheetState       [SheetState] hoisted from the caller.
 * @param modifier         Applied to the sheet.
 * @param content          Sheet content (ColumnScope receiver).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BrandBottomSheet(
    onDismissRequest: () -> Unit,
    sheetState: SheetState,
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit,
) {
    ModalBottomSheet(
        onDismissRequest = onDismissRequest,
        sheetState = sheetState,
        modifier = modifier,
        containerColor = MaterialTheme.colorScheme.surfaceContainerHigh, // surface2
        content = content,
    )
}
