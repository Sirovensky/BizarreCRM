package com.bizarreelectronics.crm.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Redo
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.data.local.draft.DraftStore

/**
 * ModalBottomSheet asking the user to resume or discard an unfinished draft
 * that DraftStore surfaced for the current feature (ActionPlan §1 L261).
 *
 * Feature screens call DraftRecoveryPrompt on first composition when
 * DraftStore.load(type) returns a non-null draft.  Caller provides:
 *   - draft:            the DraftStore.Draft snapshot
 *   - previewFormatter: maps payloadJson → short user-facing preview string
 *                       (e.g. "New ticket for John Doe — iPhone 13 screen")
 *   - onResume():       caller decodes payloadJson and restores form state
 *   - onDiscard():      caller invokes draftStore.discard(type)
 *
 * The sheet renders the Draft.savedAtMs as a relative age ("Saved 3h ago")
 * so the user can judge whether the draft is stale.  A snippet of the payload
 * preview (≤ 140 chars) gives identifiability without dumping raw JSON.
 *
 * This composable is purely presentational — it holds no state and requires
 * no ViewModel.  Immutable pattern: the caller owns [draft] and callbacks.
 *
 * @param draft             Immutable draft snapshot from DraftStore.
 * @param previewFormatter  Pure function: payloadJson → user-readable summary.
 * @param onResume          Invoked when the user taps "Resume".
 * @param onDiscard         Invoked when the user taps "Discard".
 * @param modifier          Applied to the [ModalBottomSheet] root.
 * @param nowMs             Injectable clock (defaults to System.currentTimeMillis)
 *                          enabling deterministic tests without mocking System time.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DraftRecoveryPrompt(
    draft: DraftStore.Draft,
    previewFormatter: (payloadJson: String) -> String,
    onResume: () -> Unit,
    onDiscard: () -> Unit,
    modifier: Modifier = Modifier,
    nowMs: () -> Long = System::currentTimeMillis,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    val typeLabel = draftTypeLabel(draft.type)
    val ageText = formatDraftAge(savedAtMs = draft.savedAtMs, nowMs = nowMs())
    val rawPreview = previewFormatter(draft.payloadJson)
    val preview = if (rawPreview.length > PREVIEW_MAX_CHARS) {
        rawPreview.take(PREVIEW_MAX_CHARS)
    } else {
        rawPreview
    }

    val sheetContentDescription =
        "Unfinished $typeLabel draft. $ageText. Preview: $preview. " +
        "Choose Resume to continue editing or Discard to delete."

    ModalBottomSheet(
        onDismissRequest = { /* non-dismissable on backdrop — user must choose */ },
        sheetState = sheetState,
        modifier = modifier.semantics {
            role = Role.Image   // closest structural hint; window carries dialog semantics
            contentDescription = sheetContentDescription
        },
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = SHEET_HORIZONTAL_PADDING_DP.dp)
                .padding(bottom = SHEET_BOTTOM_PADDING_DP.dp),
            verticalArrangement = Arrangement.spacedBy(SECTION_SPACING_DP.dp),
        ) {
            // ── Header ───────────────────────────────────────────────────────
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(HEADER_ICON_SPACING_DP.dp),
            ) {
                Icon(
                    imageVector = Icons.AutoMirrored.Filled.Redo,
                    contentDescription = "Resume draft icon",
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(HEADER_ICON_SIZE_DP.dp),
                )
                Text(
                    text = "Unfinished $typeLabel",
                    style = MaterialTheme.typography.titleLarge,
                    color = MaterialTheme.colorScheme.onSurface,
                )
            }

            // ── Body ─────────────────────────────────────────────────────────
            Text(
                text = "You saved a $typeLabel $ageText.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            // ── Preview card ─────────────────────────────────────────────────
            Surface(
                tonalElevation = PREVIEW_TONAL_ELEVATION_DP.dp,
                shape = MaterialTheme.shapes.small,
                modifier = Modifier
                    .fillMaxWidth()
                    .semantics(mergeDescendants = true) {
                        contentDescription = "Draft preview: $preview"
                    },
            ) {
                Text(
                    text = preview,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = PREVIEW_MAX_LINES,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.padding(PREVIEW_CARD_PADDING_DP.dp),
                )
            }

            Spacer(modifier = Modifier.height(ACTION_ROW_TOP_SPACER_DP.dp))

            // ── Action row ───────────────────────────────────────────────────
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(
                    space = ACTION_BUTTON_SPACING_DP.dp,
                    alignment = Alignment.End,
                ),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                OutlinedButton(
                    onClick = onDiscard,
                    colors = ButtonDefaults.outlinedButtonColors(
                        contentColor = MaterialTheme.colorScheme.error,
                    ),
                    modifier = Modifier.semantics {
                        contentDescription = "Discard $typeLabel draft"
                    },
                ) {
                    Text(text = "Discard")
                }

                Button(
                    onClick = onResume,
                    modifier = Modifier.semantics {
                        contentDescription = "Resume $typeLabel draft"
                    },
                ) {
                    Text(text = "Resume")
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Pure helpers — testable without Android / Compose runtime
// ---------------------------------------------------------------------------

/**
 * Format the draft's saved timestamp as a human-readable relative age.
 *
 *   now - saved < 1 min  → "just now"
 *   1 min .. <1 hr       → "Saved Nm ago"
 *   1 hr  .. <1 day      → "Saved Nh ago"
 *   1 day .. ≤30 days    → "Saved Nd ago"
 *   > 30 days            → "Saved >30 days ago (stale)"
 *
 * Clock-skew guard: if savedAtMs is in the future (savedAtMs > nowMs) the
 * elapsed duration is clamped to 0, yielding "just now".
 */
internal fun formatDraftAge(savedAtMs: Long, nowMs: Long): String {
    val elapsedMs = (nowMs - savedAtMs).coerceAtLeast(0L)

    val minutes = elapsedMs / MS_PER_MINUTE
    val hours = elapsedMs / MS_PER_HOUR
    val days = elapsedMs / MS_PER_DAY

    return when {
        elapsedMs < MS_PER_MINUTE -> "just now"
        hours < 1L -> "Saved ${minutes}m ago"
        days < 1L -> "Saved ${hours}h ago"
        days <= MAX_NON_STALE_DAYS -> "Saved ${days}d ago"
        else -> "Saved >30 days ago (stale)"
    }
}

/**
 * Returns the display label for a [DraftStore.DraftType].
 *
 *   TICKET   → "ticket"
 *   CUSTOMER → "customer"
 *   SMS      → "SMS draft"
 */
internal fun draftTypeLabel(type: DraftStore.DraftType): String = when (type) {
    DraftStore.DraftType.TICKET -> "ticket"
    DraftStore.DraftType.CUSTOMER -> "customer"
    DraftStore.DraftType.SMS -> "SMS draft"
    DraftStore.DraftType.EXPENSE -> "expense"
    DraftStore.DraftType.INVOICE -> "invoice"
}

// ---------------------------------------------------------------------------
// Private constants
// ---------------------------------------------------------------------------

private const val MS_PER_MINUTE = 60_000L
private const val MS_PER_HOUR = 3_600_000L
private const val MS_PER_DAY = 86_400_000L
private const val MAX_NON_STALE_DAYS = 30L

/** Maximum characters shown in the preview card before truncation. */
private const val PREVIEW_MAX_CHARS = 140

/** Maximum lines the preview card body text is allowed to wrap to. */
private const val PREVIEW_MAX_LINES = 3

/** Tonal elevation of the preview Surface, in dp. */
private const val PREVIEW_TONAL_ELEVATION_DP = 1

/** Padding inside the preview card, in dp. */
private const val PREVIEW_CARD_PADDING_DP = 12

/** Horizontal padding for the sheet content, in dp. */
private const val SHEET_HORIZONTAL_PADDING_DP = 24

/** Bottom padding for the sheet content (nav-bar clearance), in dp. */
private const val SHEET_BOTTOM_PADDING_DP = 32

/** Vertical gap between sheet sections, in dp. */
private const val SECTION_SPACING_DP = 12

/** Spacing between the header icon and the title text, in dp. */
private const val HEADER_ICON_SPACING_DP = 8

/** Size of the header icon, in dp. */
private const val HEADER_ICON_SIZE_DP = 24

/** Spacing between the Discard and Resume action buttons, in dp. */
private const val ACTION_BUTTON_SPACING_DP = 8

/** Extra vertical space inserted above the action row, in dp. */
private const val ACTION_ROW_TOP_SPACER_DP = 4
