package com.bizarreelectronics.crm.ui.commandpalette

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Assignment
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Inventory
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.Receipt
import androidx.compose.material.icons.filled.Security
import androidx.compose.material.icons.filled.Sms
import androidx.compose.material.icons.filled.Star
import androidx.compose.ui.graphics.vector.ImageVector
import com.bizarreelectronics.crm.util.FtsQuerySanitizer

// ─── Command model ────────────────────────────────────────────────────────────

/**
 * Represents a single registered command in the command palette.
 *
 * @param id        Stable unique identifier (used as LazyColumn key).
 * @param label     Display label shown in the palette list.
 * @param group     Group header for visual separation (Navigation, Actions, …).
 * @param icon      Leading icon. Null = show generic circle.
 * @param keywords  Additional search tokens beyond [label] (not shown in UI).
 * @param route     Navigation route to push when command is executed. Null for
 *                  commands that trigger side-effects via [action].
 * @param action    Optional side-effect invoked AFTER navigation (or instead of it).
 * @param adminOnly If true, command is hidden unless the current user is admin.
 */
data class Command(
    val id: String,
    val label: String,
    val group: CommandGroup,
    val icon: ImageVector? = null,
    val keywords: List<String> = emptyList(),
    val route: String? = null,
    val action: (() -> Unit)? = null,
    val adminOnly: Boolean = false,
)

enum class CommandGroup(val displayName: String) {
    NAVIGATION("Go to"),
    ACTIONS("Actions"),
    RECENT("Recent"),
}

// ─── Static registry ──────────────────────────────────────────────────────────

/**
 * §54 — Command palette registry.
 *
 * [staticCommands] contains navigation destinations and common actions known
 * at compile time. [DynamicCommandProvider] is the injection point for
 * runtime data such as recent entities resolved from the view model.
 *
 * Querying: [CommandRegistry.search] filters both label and keywords, groups
 * results, and returns them in display order (NAVIGATION → ACTIONS → RECENT).
 */
object CommandRegistry {

    val staticCommands: List<Command> = listOf(
        // ─── Navigation ───────────────────────────────────────────────────────
        Command(
            id = "nav:dashboard",
            label = "Go to Dashboard",
            group = CommandGroup.NAVIGATION,
            icon = Icons.Default.Star,
            keywords = listOf("home", "overview"),
            route = "dashboard",
        ),
        Command(
            id = "nav:tickets",
            label = "Go to Tickets",
            group = CommandGroup.NAVIGATION,
            icon = Icons.Default.Assignment,
            keywords = listOf("repairs", "jobs", "work orders"),
            route = "tickets",
        ),
        Command(
            id = "nav:customers",
            label = "Go to Customers",
            group = CommandGroup.NAVIGATION,
            icon = Icons.Default.Person,
            keywords = listOf("contacts", "clients"),
            route = "customers",
        ),
        Command(
            id = "nav:invoices",
            label = "Go to Invoices",
            group = CommandGroup.NAVIGATION,
            icon = Icons.Default.Receipt,
            keywords = listOf("billing", "payments"),
            route = "invoices",
        ),
        Command(
            id = "nav:inventory",
            label = "Go to Inventory",
            group = CommandGroup.NAVIGATION,
            icon = Icons.Default.Inventory,
            keywords = listOf("parts", "stock", "items"),
            route = "inventory",
        ),
        Command(
            id = "nav:reports",
            label = "Go to Reports",
            group = CommandGroup.NAVIGATION,
            icon = Icons.Default.BarChart,
            keywords = listOf("analytics", "sales", "stats"),
            route = "reports",
        ),
        Command(
            id = "nav:messages",
            label = "Go to Messages",
            group = CommandGroup.NAVIGATION,
            icon = Icons.Default.Sms,
            keywords = listOf("sms", "texts", "chat"),
            route = "messages",
        ),
        Command(
            id = "nav:audit",
            label = "Go to Audit Log",
            group = CommandGroup.NAVIGATION,
            icon = Icons.Default.History,
            keywords = listOf("audit", "logs", "admin", "history"),
            route = "audit-logs",
            adminOnly = true,
        ),
        Command(
            id = "nav:security",
            label = "Go to Security Summary",
            group = CommandGroup.NAVIGATION,
            icon = Icons.Default.Security,
            keywords = listOf("security", "sessions", "2fa"),
            route = "settings/security/summary",
            adminOnly = true,
        ),

        // ─── Actions ──────────────────────────────────────────────────────────
        Command(
            id = "action:new-ticket",
            label = "New ticket",
            group = CommandGroup.ACTIONS,
            icon = Icons.Default.Add,
            keywords = listOf("create ticket", "repair", "intake"),
            route = "ticket-create",
        ),
        Command(
            id = "action:new-customer",
            label = "New customer",
            group = CommandGroup.ACTIONS,
            icon = Icons.Default.Add,
            keywords = listOf("add customer", "new contact"),
            route = "customer-create",
        ),
        Command(
            id = "action:new-invoice",
            label = "New invoice",
            group = CommandGroup.ACTIONS,
            icon = Icons.Default.Add,
            keywords = listOf("create invoice", "billing"),
            route = "invoice-create",
        ),
        Command(
            id = "action:scan-barcode",
            label = "Scan barcode",
            group = CommandGroup.ACTIONS,
            icon = Icons.Default.QrCodeScanner,
            keywords = listOf("scan", "camera", "qr", "barcode"),
            route = "scanner",
        ),
        Command(
            id = "action:new-sms",
            label = "New SMS",
            group = CommandGroup.ACTIONS,
            icon = Icons.Default.Sms,
            keywords = listOf("send sms", "message", "text"),
            route = "messages",
        ),
    )

    /**
     * Filter [staticCommands] + [dynamicCommands] by [query], respecting
     * [isAdmin]. Returns results grouped in display order, capped at 20 items.
     *
     * Matching priority:
     *  1. Exact/prefix substring match on label or keyword (fast path).
     *  2. Fuzzy Levenshtein match (edit distance ≤ 2) via [FtsQuerySanitizer]
     *     on words ≥ 4 chars — recovers from typos without flooding results.
     *
     * [recentCommandIds] are promoted to [CommandGroup.RECENT] and sorted
     * by recency order within their group.
     */
    fun search(
        query: String,
        isAdmin: Boolean,
        dynamicCommands: List<Command> = emptyList(),
        recentCommandIds: List<String> = emptyList(),
    ): List<Command> {
        val q = query.trim().lowercase()
        val allCommands = staticCommands + dynamicCommands

        // Build a promoted copy for any command that appears in recentCommandIds,
        // so its group is RECENT and ordering reflects recency (index in the list).
        val recentSet = recentCommandIds.toSet()
        val promotedCommands = allCommands.map { cmd ->
            if (cmd.id in recentSet) cmd.copy(group = CommandGroup.RECENT) else cmd
        }

        val queryWords = q.split(Regex("\\s+")).filter { it.isNotBlank() }

        val candidates = promotedCommands.filter { cmd ->
            if (cmd.adminOnly && !isAdmin) return@filter false
            if (q.isBlank()) return@filter true

            // 1. Substring match on label or any keyword (fast path)
            val substringHit = cmd.label.lowercase().contains(q) ||
                cmd.keywords.any { kw -> kw.lowercase().contains(q) }
            if (substringHit) return@filter true

            // 2. Fuzzy match: any query word within Levenshtein ≤ 2 of a label
            //    token or keyword token (guards against short words via
            //    FtsQuerySanitizer.MIN_LENGTH_FOR_FUZZY = 4).
            val searchableText = (listOf(cmd.label) + cmd.keywords).joinToString(" ")
            FtsQuerySanitizer.isFuzzyMatch(queryWords, searchableText)
        }

        // Sort: NAVIGATION → ACTIONS → RECENT; within RECENT respect recency order.
        val recentOrder = recentCommandIds.withIndex().associate { (idx, id) -> id to idx }
        return candidates
            .sortedWith(
                compareBy(
                    { it.group.ordinal },
                    { if (it.group == CommandGroup.RECENT) recentOrder[it.id] ?: Int.MAX_VALUE else 0 },
                    { it.label },
                ),
            )
            .take(20)
    }
}

// ─── Dynamic provider interface ───────────────────────────────────────────────

/**
 * Inject implementations to provide runtime commands (e.g. recent entities).
 * The command palette ViewModel collects all providers and merges their lists.
 */
interface DynamicCommandProvider {
    fun provide(): List<Command>
}
