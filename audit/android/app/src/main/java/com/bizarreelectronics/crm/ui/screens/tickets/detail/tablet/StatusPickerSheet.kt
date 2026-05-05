package com.bizarreelectronics.crm.ui.screens.tickets.detail.tablet

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.data.remote.dto.TicketStatusItem

/**
 * Tablet status-picker bottom sheet (Option B from the planning round).
 *
 * Tap on the cream Status pill in `TabletTopAppBar` opens this sheet.
 * Shows every server-supplied status with its colour swatch + name +
 * the current selection highlighted. Tap any row → invokes
 * [onStatusSelected] with the new status id; the host then routes to
 * the existing `requestStatusChangeWithNotify` flow (notify-preview
 * dialog + SMS opt-in).
 *
 * On a 1280-dp tablet `ModalBottomSheet` defaults to full-width which
 * looks awkward — the inner [Column] is therefore constrained to
 * `widthIn(max = 560.dp)` and centered. Phones never see this sheet
 * (the tablet layout is gated behind `isCompactWidth()`).
 *
 * @param currentStatusId id of the currently-applied status; that row
 *   shows a "current" badge and other rows below.
 * @param statuses server-supplied list (already loaded into VM state).
 * @param onStatusSelected fires with the picked status id and closes
 *   the sheet via [onDismiss].
 * @param onDismiss user dismissed without picking — close the sheet.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun StatusPickerSheet(
    currentStatusId: Long?,
    statuses: List<TicketStatusItem>,
    onStatusSelected: (Long) -> Unit,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = MaterialTheme.colorScheme.surface,
    ) {
        Column(
            modifier = Modifier
                .widthIn(max = 560.dp)
                .align(Alignment.CenterHorizontally)
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 4.dp),
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            Text(
                "Change status",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier
                    .padding(start = 4.dp, top = 4.dp, bottom = 12.dp)
                    .semantics { contentDescription = "Change ticket status" },
            )

            statuses.forEach { status ->
                val isCurrent = status.id == currentStatusId
                Surface(
                    color = if (isCurrent) MaterialTheme.colorScheme.surfaceVariant
                    else Color.Transparent,
                    shape = RoundedCornerShape(12.dp),
                    onClick = {
                        if (!isCurrent) onStatusSelected(status.id)
                        else onDismiss()
                    },
                    modifier = Modifier
                        .fillMaxWidth()
                        .semantics {
                            contentDescription = if (isCurrent)
                                "${status.name} (current status)"
                            else "Change to ${status.name}"
                        },
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        // Colour swatch from server-supplied hex (or fallback).
                        val swatch = remember(status.color) {
                            runCatching {
                                Color(android.graphics.Color.parseColor(status.color ?: "#6b7280"))
                            }.getOrDefault(Color(0xFF6b7280))
                        }
                        Surface(
                            shape = CircleShape,
                            color = swatch,
                            modifier = Modifier.size(10.dp),
                        ) {}

                        Text(
                            status.name,
                            style = MaterialTheme.typography.bodyLarge,
                            color = MaterialTheme.colorScheme.onSurface,
                            modifier = Modifier.weight(1f),
                        )

                        if (isCurrent) {
                            Text(
                                "current",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
            }

            Spacer(Modifier.height(16.dp))
        }
    }
}

// remember helper — top-level so it's available without extra imports.
@Composable
private fun <T> remember(key: Any?, calculation: () -> T): T =
    androidx.compose.runtime.remember(key) { calculation() }
