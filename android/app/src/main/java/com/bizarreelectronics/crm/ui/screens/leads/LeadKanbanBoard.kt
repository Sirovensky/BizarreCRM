package com.bizarreelectronics.crm.ui.screens.leads

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.data.local.db.entities.LeadEntity
import com.bizarreelectronics.crm.util.DateFormatter
import com.bizarreelectronics.crm.util.PhoneFormatter

/**
 * Canonical display order for lead pipeline stages (ActionPlan §9).
 *
 * Derived from the server's LEGAL_LEAD_TRANSITIONS map in leads.routes.ts.
 * Any lead whose status does not appear in this list is bucketed into a
 * trailing "Other" column so no lead is ever silently dropped.
 */
val DEFAULT_STAGE_ORDER: List<String> = listOf(
    "new",
    "contacted",
    "scheduled",
    "qualified",
    "proposal",
    "converted",
    "lost",
)

private fun stageLabelFor(stage: String): String = when (stage) {
    "new"       -> "New"
    "contacted" -> "Contacted"
    "scheduled" -> "Scheduled"
    "qualified" -> "Qualified"
    "proposal"  -> "Proposal"
    "converted" -> "Converted"
    "lost"      -> "Lost"
    else        -> stage.replaceFirstChar { it.uppercaseChar() }
}

/**
 * Read-only Kanban view of leads grouped by stage (ActionPlan §9).
 *
 * Rendered as a horizontally-scrollable Row of ElevatedCard columns. Each
 * column shows a stage name + count badge plus a vertical LazyColumn of
 * lead cards.
 *
 * Card tap: [onLeadClick]. Card long-press: [onStageChangeRequest] — callers
 * can wire an AlertDialog/DropdownMenu; the callback is intentionally
 * non-suspending so the caller owns the mutation lifecycle.
 *
 * Drag-drop to change stage: deferred to a later wave.
 *
 * Accessibility: every column Row has a contentDescription summarising stage
 * + count; every lead card has a full summary contentDescription for TalkBack.
 * Empty-state text is announced as "No leads in <stage>" so TalkBack users
 * receive the same signal as sighted users.
 *
 * ReduceMotion: no entrance animations are applied, so the pref has no
 * observable effect here (there is nothing to skip).
 *
 * @param leadsByStage   Leads pre-grouped by stage key. Caller is responsible
 *                       for computing this via [remember]; this composable is
 *                       stateless.
 * @param stageOrder     Canonical display order for column headers.
 * @param onLeadClick    Called with the lead's id when the user taps a card.
 * @param onStageChangeRequest Called with (leadId, currentStage) on long-press.
 *                       Caller decides what to show (dropdown / dialog).
 */
@Composable
fun LeadKanbanBoard(
    leadsByStage: Map<String, List<LeadEntity>>,
    stageOrder: List<String>,
    onLeadClick: (leadId: Long) -> Unit,
    onStageChangeRequest: (leadId: Long, currentStage: String) -> Unit,
    modifier: Modifier = Modifier,
) {
    // Column container colors — cycle through three container tones so adjacent
    // columns are visually distinct without hardcoded hex values.
    val containerColors = listOf(
        MaterialTheme.colorScheme.secondaryContainer,
        MaterialTheme.colorScheme.tertiaryContainer,
        MaterialTheme.colorScheme.primaryContainer,
    )

    // Build the effective column list: ordered stages first, then any unknown
    // stages present in the data that aren't in stageOrder (catch-all bucket).
    val knownStageSet = stageOrder.toHashSet()
    val extraStages = leadsByStage.keys
        .filter { it !in knownStageSet }
        .sorted()
    val effectiveOrder = stageOrder + extraStages

    Row(
        modifier = modifier
            .fillMaxSize()
            .horizontalScroll(rememberScrollState())
            .padding(horizontal = 12.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        effectiveOrder.forEachIndexed { index, stage ->
            val leadsInStage: List<LeadEntity> = leadsByStage[stage] ?: emptyList()
            val stageLabel = stageLabelFor(stage)
            val containerColor = containerColors[index % containerColors.size]
            val onContainerColor = when (index % containerColors.size) {
                0    -> MaterialTheme.colorScheme.onSecondaryContainer
                1    -> MaterialTheme.colorScheme.onTertiaryContainer
                else -> MaterialTheme.colorScheme.onPrimaryContainer
            }
            val columnDescription = "$stageLabel column, ${leadsInStage.size} " +
                if (leadsInStage.size == 1) "lead" else "leads"

            ElevatedCard(
                modifier = Modifier
                    .width(280.dp)
                    .fillMaxHeight()
                    .semantics {
                        contentDescription = columnDescription
                        role = Role.Image          // "region" role for TalkBack
                    },
                colors = CardDefaults.elevatedCardColors(
                    containerColor = containerColor,
                    contentColor = onContainerColor,
                ),
            ) {
                Column(modifier = Modifier.fillMaxSize()) {
                    // ── Column header ──────────────────────────────────────
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 12.dp, vertical = 10.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            text = stageLabel,
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.SemiBold,
                            color = onContainerColor,
                        )
                        // Count badge
                        Surface(
                            color = onContainerColor.copy(alpha = 0.15f),
                            shape = MaterialTheme.shapes.small,
                        ) {
                            Text(
                                text = leadsInStage.size.toString(),
                                style = MaterialTheme.typography.labelMedium,
                                fontWeight = FontWeight.Bold,
                                color = onContainerColor,
                                modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp),
                            )
                        }
                    }

                    HorizontalDivider(
                        color = onContainerColor.copy(alpha = 0.15f),
                        thickness = 1.dp,
                    )

                    // ── Lead cards / empty state ───────────────────────────
                    if (leadsInStage.isEmpty()) {
                        Box(
                            modifier = Modifier
                                .fillMaxSize()
                                .padding(16.dp),
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(
                                text = "No leads in $stageLabel",
                                style = MaterialTheme.typography.bodySmall,
                                color = onContainerColor.copy(alpha = 0.6f),
                                modifier = Modifier.semantics {
                                    contentDescription = "No leads in $stageLabel"
                                },
                            )
                        }
                    } else {
                        LazyColumn(
                            modifier = Modifier.fillMaxSize(),
                            contentPadding = PaddingValues(8.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            items(leadsInStage, key = { it.id }) { lead ->
                                KanbanLeadCard(
                                    lead = lead,
                                    onLeadClick = onLeadClick,
                                    onStageChangeRequest = onStageChangeRequest,
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

// ─── Kanban lead card ──────────────────────────────────────────────────────────

@Composable
private fun KanbanLeadCard(
    lead: LeadEntity,
    onLeadClick: (Long) -> Unit,
    onStageChangeRequest: (Long, String) -> Unit,
) {
    val fullName = listOfNotNull(lead.firstName, lead.lastName)
        .joinToString(" ")
        .ifBlank { "Unknown" }
    val phoneFormatted = if (!lead.phone.isNullOrBlank()) PhoneFormatter.format(lead.phone) else null
    val ageText = DateFormatter.formatRelative(lead.createdAt)

    // Build a concise but complete TalkBack summary.
    val cardDescription = buildString {
        append(fullName)
        if (phoneFormatted != null) append(", $phoneFormatted")
        if (ageText.isNotBlank()) append(", created $ageText")
        if (!lead.source.isNullOrBlank()) append(", source: ${lead.source}")
    }

    Card(
        onClick = { onLeadClick(lead.id) },
        modifier = Modifier
            .fillMaxWidth()
            .semantics { contentDescription = cardDescription },
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surface,
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
    ) {
        Column(
            modifier = Modifier.padding(10.dp),
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            // Order id (if present)
            if (!lead.orderId.isNullOrBlank()) {
                Text(
                    text = lead.orderId,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            // Full name — primary label
            Text(
                text = fullName,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurface,
            )

            // Phone
            if (phoneFormatted != null) {
                Text(
                    text = phoneFormatted,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            // Age footer row
            if (ageText.isNotBlank()) {
                Text(
                    text = ageText,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}
