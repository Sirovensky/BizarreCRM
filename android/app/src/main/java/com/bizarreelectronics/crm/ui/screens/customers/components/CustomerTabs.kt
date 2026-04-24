@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package com.bizarreelectronics.crm.ui.screens.customers.components

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.PrimaryTabRow
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.data.local.db.entities.CustomerEntity
import com.bizarreelectronics.crm.data.remote.dto.CustomerAsset
import com.bizarreelectronics.crm.data.remote.dto.CustomerAnalytics
import com.bizarreelectronics.crm.data.remote.dto.CustomerHealthScore
import com.bizarreelectronics.crm.data.remote.dto.CustomerLtvTier
import com.bizarreelectronics.crm.data.remote.dto.CustomerNote
import com.bizarreelectronics.crm.data.remote.dto.InvoiceListItem
import com.bizarreelectronics.crm.data.remote.dto.TicketListItem
import com.bizarreelectronics.crm.ui.components.shared.BrandCard
import com.bizarreelectronics.crm.util.DateFormatter
import com.bizarreelectronics.crm.util.formatAsMoney
import com.bizarreelectronics.crm.util.toCentsOrZero

private val TABS = listOf("Info", "Tickets", "Invoices", "Communications", "Assets")

/**
 * Five-tab layout for the customer detail screen (plan:L889–L900).
 *
 * Tabs: Info / Tickets / Invoices / Communications / Assets.
 * Tab state survives rotation via [rememberSaveable].
 *
 * @param customer        Room entity (contact fields).
 * @param analytics       Analytics quick-stats; null = not loaded.
 * @param healthScore     Health score ring data; null = not loaded or 404.
 * @param ltvTier         LTV tier chip data; null = not loaded or 404.
 * @param recentTickets   Ticket tab data; null = loading.
 * @param invoices        Invoice tab data; null = loading.
 * @param notes           Communications tab data; null = loading.
 * @param assets          Assets tab data; null = loading.
 * @param noteDraft       Current note composer text.
 * @param isPostingNote   True while a note POST is in flight.
 * @param onNoteDraftChange Note draft change callback.
 * @param onPostNote      Post note callback.
 * @param onNavigateToTicket Navigate to ticket detail.
 * @param onCreateTicket  Create ticket callback.
 * @param onCall          Call primary phone.
 * @param onSms           SMS primary phone.
 * @param onShare         Share vCard.
 * @param onDelete        Delete customer.
 * @param onRecalculateHealth Trigger health score recalculation.
 */
@Composable
fun CustomerDetailTabs(
    customer: CustomerEntity,
    analytics: CustomerAnalytics?,
    healthScore: CustomerHealthScore?,
    ltvTier: CustomerLtvTier?,
    recentTickets: List<TicketListItem>?,
    invoices: List<InvoiceListItem>?,
    notes: List<CustomerNote>?,
    assets: List<CustomerAsset>?,
    noteDraft: String,
    isPostingNote: Boolean,
    onNoteDraftChange: (String) -> Unit,
    onPostNote: () -> Unit,
    onNavigateToTicket: (Long) -> Unit,
    onCreateTicket: (() -> Unit)?,
    onCall: ((String) -> Unit)?,
    onSms: ((String) -> Unit)?,
    onShare: (() -> Unit)? = null,
    onDelete: (() -> Unit)? = null,
    onRecalculateHealth: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    var selectedTab by rememberSaveable { mutableIntStateOf(0) }

    Column(modifier = modifier.fillMaxWidth()) {
        PrimaryTabRow(selectedTabIndex = selectedTab) {
            TABS.forEachIndexed { index, title ->
                Tab(
                    selected = selectedTab == index,
                    onClick = { selectedTab = index },
                    text = { Text(title) },
                )
            }
        }

        AnimatedContent(
            targetState = selectedTab,
            transitionSpec = {
                fadeIn(tween(200)) togetherWith fadeOut(tween(200))
            },
            label = "customer_tab_content",
        ) { tab ->
            when (tab) {
                0 -> InfoTab(
                    customer = customer,
                    analytics = analytics,
                    healthScore = healthScore,
                    ltvTier = ltvTier,
                    onCall = onCall,
                    onSms = onSms,
                    onCreateTicket = onCreateTicket,
                    onShare = onShare,
                    onDelete = onDelete,
                    onRecalculateHealth = onRecalculateHealth,
                )
                1 -> TicketsTab(
                    tickets = recentTickets,
                    onNavigateToTicket = onNavigateToTicket,
                )
                2 -> InvoicesTab(invoices = invoices)
                3 -> CommunicationsTab(
                    notes = notes,
                    noteDraft = noteDraft,
                    isPostingNote = isPostingNote,
                    onNoteDraftChange = onNoteDraftChange,
                    onPostNote = onPostNote,
                )
                4 -> AssetsTab(assets = assets)
            }
        }
    }
}

// ─── Info tab ───────────────────────────────────────────────────────────────

@Composable
private fun InfoTab(
    customer: CustomerEntity,
    analytics: CustomerAnalytics?,
    healthScore: CustomerHealthScore?,
    ltvTier: CustomerLtvTier?,
    onCall: ((String) -> Unit)?,
    onSms: ((String) -> Unit)?,
    onCreateTicket: (() -> Unit)?,
    onShare: (() -> Unit)?,
    onDelete: (() -> Unit)?,
    onRecalculateHealth: (() -> Unit)?,
) {
    val primaryPhone = customer.mobile ?: customer.phone

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // Health score + LTV row
        if (healthScore != null || ltvTier != null) {
            item {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    if (healthScore != null) {
                        HealthScoreRing(
                            score = healthScore.score,
                            tier = healthScore.tier,
                            onRecalculate = onRecalculateHealth,
                            modifier = Modifier.weight(1f),
                        )
                    }
                    if (ltvTier != null) {
                        LtvTierChip(
                            tier = ltvTier.tier,
                            lifetimeValue = ltvTier.lifetimeValue,
                            modifier = Modifier.weight(1f),
                        )
                    }
                }
            }
        }

        // Quick actions chip row
        item {
            CustomerQuickActions(
                phone = primaryPhone,
                email = customer.email,
                onCall = primaryPhone?.let { p -> onCall?.let { { it(p) } } },
                onSms = primaryPhone?.let { p -> onSms?.let { { it(p) } } },
                onNewTicket = onCreateTicket,
                onShare = onShare,
                onDelete = onDelete,
            )
        }
    }
}

// ─── Health score ring (plan:L892) ──────────────────────────────────────────

@Composable
private fun HealthScoreRing(
    score: Int,
    tier: String?,
    onRecalculate: (() -> Unit)?,
    modifier: Modifier = Modifier,
) {
    val ringColor = when {
        score >= 70 -> MaterialTheme.colorScheme.primary
        score >= 40 -> MaterialTheme.colorScheme.tertiary
        else -> MaterialTheme.colorScheme.error
    }

    BrandCard(modifier = modifier) {
        Column(
            modifier = Modifier.padding(12.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                "Health",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(modifier = Modifier.height(4.dp))
            Box(contentAlignment = Alignment.Center) {
                CircularProgressIndicator(
                    progress = { score / 100f },
                    modifier = Modifier.size(56.dp),
                    color = ringColor,
                    strokeWidth = 6.dp,
                )
                Text(
                    "$score",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.Bold,
                    color = ringColor,
                )
            }
            if (tier != null) {
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    tier,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

// ─── LTV tier chip (plan:L893) ──────────────────────────────────────────────

@Composable
private fun LtvTierChip(
    tier: String,
    lifetimeValue: Double,
    modifier: Modifier = Modifier,
) {
    val chipColor = when (tier) {
        "VIP" -> MaterialTheme.colorScheme.primaryContainer
        "At-Risk" -> MaterialTheme.colorScheme.errorContainer
        else -> MaterialTheme.colorScheme.surfaceVariant
    }
    val chipContent = when (tier) {
        "VIP" -> MaterialTheme.colorScheme.onPrimaryContainer
        "At-Risk" -> MaterialTheme.colorScheme.onErrorContainer
        else -> MaterialTheme.colorScheme.onSurfaceVariant
    }

    BrandCard(modifier = modifier) {
        Column(
            modifier = Modifier.padding(12.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                "LTV",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(modifier = Modifier.height(4.dp))
            androidx.compose.material3.Surface(
                color = chipColor,
                shape = MaterialTheme.shapes.small,
            ) {
                Text(
                    tier,
                    modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp),
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = chipContent,
                )
            }
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                "$${lifetimeValue.toLong()}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

// ─── Tickets tab (plan:L897) ─────────────────────────────────────────────────

@Composable
private fun TicketsTab(
    tickets: List<TicketListItem>?,
    onNavigateToTicket: (Long) -> Unit,
) {
    if (tickets == null) {
        LoadingPlaceholder()
        return
    }
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        if (tickets.isEmpty()) {
            item {
                EmptyTabMessage("No tickets yet")
            }
        } else {
            items(tickets, key = { it.id }) { ticket ->
                TicketTabRow(ticket = ticket, onClick = { onNavigateToTicket(ticket.id) })
            }
        }
    }
}

@Composable
private fun TicketTabRow(ticket: TicketListItem, onClick: () -> Unit) {
    BrandCard(
        modifier = Modifier.fillMaxWidth(),
        onClick = onClick,
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    ticket.orderId,
                    style = MaterialTheme.typography.labelLarge,
                    fontWeight = FontWeight.Medium,
                )
                val device = ticket.firstDevice?.deviceName.orEmpty()
                if (device.isNotBlank()) {
                    Text(
                        device,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            val status = ticket.statusName
            if (!status.isNullOrBlank()) {
                Text(
                    status,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.primary,
                )
            }
        }
    }
}

// ─── Invoices tab (plan:L897) ────────────────────────────────────────────────

@Composable
private fun InvoicesTab(invoices: List<InvoiceListItem>?) {
    if (invoices == null) {
        LoadingPlaceholder()
        return
    }
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        if (invoices.isEmpty()) {
            item { EmptyTabMessage("No invoices yet") }
        } else {
            items(invoices, key = { it.id }) { invoice ->
                InvoiceTabRow(invoice)
            }
        }
    }
}

@Composable
private fun InvoiceTabRow(invoice: InvoiceListItem) {
    BrandCard(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    "#${invoice.id}",
                    style = MaterialTheme.typography.labelLarge,
                    fontWeight = FontWeight.Medium,
                )
                if (!invoice.createdAt.isNullOrBlank()) {
                    Text(
                        DateFormatter.formatAbsolute(invoice.createdAt),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            Text(
                invoice.total?.toCentsOrZero()?.formatAsMoney() ?: "-",
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.primary,
            )
        }
    }
}

// ─── Communications tab (plan:L897) ──────────────────────────────────────────

@Composable
private fun CommunicationsTab(
    notes: List<CustomerNote>?,
    noteDraft: String,
    isPostingNote: Boolean,
    onNoteDraftChange: (String) -> Unit,
    onPostNote: () -> Unit,
) {
    if (notes == null) {
        LoadingPlaceholder()
        return
    }
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        if (notes.isEmpty()) {
            item { EmptyTabMessage("No communications yet") }
        } else {
            items(notes, key = { it.id }) { note ->
                NoteTabRow(note)
            }
        }
    }
}

@Composable
private fun NoteTabRow(note: CustomerNote) {
    BrandCard(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(12.dp)) {
            Text(note.body, style = MaterialTheme.typography.bodyMedium)
            Spacer(modifier = Modifier.height(2.dp))
            val author = note.authorUsername?.takeIf { it.isNotBlank() } ?: "—"
            Text(
                "$author · ${DateFormatter.formatRelative(note.createdAt)}",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

// ─── Assets tab (plan:L897) ──────────────────────────────────────────────────

@Composable
private fun AssetsTab(assets: List<CustomerAsset>?) {
    if (assets == null) {
        LoadingPlaceholder()
        return
    }
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        if (assets.isEmpty()) {
            item { EmptyTabMessage("No assets registered") }
        } else {
            items(assets, key = { it.id }) { asset ->
                AssetTabRow(asset)
            }
        }
    }
}

@Composable
private fun AssetTabRow(asset: CustomerAsset) {
    BrandCard(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(12.dp)) {
            Text(
                asset.name ?: "Asset #${asset.id}",
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Medium,
            )
            listOfNotNull(
                asset.imei?.let { "IMEI: $it" },
                asset.serial?.let { "Serial: $it" },
                asset.color?.let { "Color: $it" },
            ).forEach { line ->
                Text(
                    line,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

// ─── Shared helpers ───────────────────────────────────────────────────────────

@Composable
private fun LoadingPlaceholder() {
    Box(modifier = Modifier.fillMaxSize().padding(32.dp), contentAlignment = Alignment.Center) {
        CircularProgressIndicator()
    }
}

@Composable
private fun EmptyTabMessage(message: String) {
    Text(
        message,
        style = MaterialTheme.typography.bodyMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
}
