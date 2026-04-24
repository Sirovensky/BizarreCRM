import SwiftUI
import Core
import DesignSystem

// MARK: - KioskQueueEntry

/// §22 A single entry on the customer-facing queue board.
public struct KioskQueueEntry: Identifiable, Sendable, Equatable {
    public let id: Int64
    /// Short human-visible ticket identifier (e.g. "TK-0042").
    public let displayId: String
    /// Customer first name only — avoid surname on a public display.
    public let customerFirstName: String
    /// Plain-text description of the device being serviced.
    public let deviceSummary: String?
    /// Current status of the ticket.
    public let status: TicketStatus
    /// When the ticket was last updated — used for relative time stamps.
    public let updatedAt: Date

    public init(
        id: Int64,
        displayId: String,
        customerFirstName: String,
        deviceSummary: String? = nil,
        status: TicketStatus,
        updatedAt: Date
    ) {
        self.id = id
        self.displayId = displayId
        self.customerFirstName = customerFirstName
        self.deviceSummary = deviceSummary
        self.status = status
        self.updatedAt = updatedAt
    }
}

// MARK: - KioskQueueEntry factory from Ticket

public extension KioskQueueEntry {
    /// Creates a public-facing `KioskQueueEntry` from a full `Ticket` model,
    /// stripping surname to protect customer privacy on a shared display.
    init(ticket: Ticket) {
        let firstName = ticket.customerName
            .components(separatedBy: " ")
            .first ?? ticket.customerName
        self.init(
            id: ticket.id,
            displayId: ticket.displayId,
            customerFirstName: firstName,
            deviceSummary: ticket.deviceSummary,
            status: ticket.status,
            updatedAt: ticket.updatedAt
        )
    }
}

// MARK: - KioskQueueBoardConfig

/// §22 Display configuration for the queue board.
public struct KioskQueueBoardConfig: Sendable, Equatable {
    /// Title shown in the board header (e.g. "Service Queue").
    public let headerTitle: String
    /// Statuses to highlight as "ready for pickup".
    public let readyStatuses: Set<TicketStatus>
    /// Maximum number of entries shown before truncation.
    public let maxVisibleEntries: Int

    public init(
        headerTitle: String = "Service Queue",
        readyStatuses: Set<TicketStatus> = [.ready],
        maxVisibleEntries: Int = 12
    ) {
        self.headerTitle = headerTitle
        self.readyStatuses = readyStatuses
        self.maxVisibleEntries = maxVisibleEntries
    }
}

// MARK: - KioskQueueBoard

/// §22 Customer-facing ticket queue display for iPad kiosk.
///
/// Shows a scrollable grid of in-progress and ready tickets. Ready tickets
/// are highlighted with a brand-orange glass accent to draw customer attention.
///
/// Liquid Glass chrome: column headers use `.brandGlass(.regular)`, ready
/// ticket rows use `.brandGlass(.identity, tint: .orange)`.
///
/// Designed for landscape orientation. In portrait the grid collapses to a
/// single column via `LazyVGrid`.
public struct KioskQueueBoard: View {
    private let entries: [KioskQueueEntry]
    private let config: KioskQueueBoardConfig
    private let metrics: KioskLayoutMetrics

    @Environment(\.kioskDisplayVariant) private var variant

    public init(
        entries: [KioskQueueEntry],
        config: KioskQueueBoardConfig = KioskQueueBoardConfig(),
        metrics: KioskLayoutMetrics
    ) {
        self.entries = entries
        self.config = config
        self.metrics = metrics
    }

    // MARK: - Layout helpers

    private var visibleEntries: [KioskQueueEntry] {
        Array(entries.prefix(config.maxVisibleEntries))
    }

    private var columns: [GridItem] {
        let count = variant == .portrait ? 1 : 2
        return Array(
            repeating: GridItem(.flexible(), spacing: DesignTokens.Spacing.lg),
            count: count
        )
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            boardHeader
            boardContent
        }
    }

    // MARK: - Header

    private var boardHeader: some View {
        HStack {
            Image(systemName: "list.bullet.clipboard")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            Text(config.headerTitle)
                .font(.title2.bold())
                .foregroundStyle(.primary)

            Spacer()

            entryCountBadge
        }
        .padding(.horizontal, metrics.horizontalPadding)
        .padding(.vertical, DesignTokens.Spacing.lg)
        .brandGlass(.regular, in: Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(config.headerTitle). \(entries.count) ticket\(entries.count == 1 ? "" : "s") in queue.")
    }

    @ViewBuilder
    private var entryCountBadge: some View {
        if !entries.isEmpty {
            BrandGlassBadge("\(entries.count)", variant: .identity, tint: .orange)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var boardContent: some View {
        if entries.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: DesignTokens.Spacing.lg) {
                    ForEach(visibleEntries) { entry in
                        KioskQueueEntryCard(
                            entry: entry,
                            isReady: config.readyStatuses.contains(entry.status)
                        )
                    }
                }
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.vertical, metrics.verticalPadding)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("All caught up!")
                .font(.title3.bold())
                .foregroundStyle(.primary)
            Text("No tickets in the queue right now.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(metrics.horizontalPadding)
    }
}

// MARK: - KioskQueueEntryCard

/// §22 Individual ticket card on the queue board.
struct KioskQueueEntryCard: View {
    let entry: KioskQueueEntry
    let isReady: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack {
                Text(entry.displayId)
                    .font(.system(.headline, design: .monospaced).bold())
                    .foregroundStyle(isReady ? Color.orange : Color.primary)
                Spacer()
                statusChip
            }

            Text(entry.customerFirstName)
                .font(.title3.bold())
                .foregroundStyle(.primary)
                .lineLimit(1)

            if let device = entry.deviceSummary {
                Text(device)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Text(entry.updatedAt, style: .relative)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(DesignTokens.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(cardAccessibilityLabel)
    }

    // MARK: - Status chip

    private var statusChip: some View {
        Text(entry.status.displayName)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xxs)
            .background(
                isReady ? Color.orange.opacity(0.2) : Color.secondary.opacity(0.12),
                in: Capsule()
            )
            .foregroundStyle(isReady ? Color.orange : Color.secondary)
    }

    // MARK: - Card background

    @ViewBuilder
    private var cardBackground: some View {
        if isReady {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .fill(Color.orange.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                        .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1.5)
                )
        } else {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .fill(.regularMaterial)
        }
    }

    // MARK: - Accessibility

    private var cardAccessibilityLabel: String {
        var parts = [
            "Ticket \(entry.displayId)",
            entry.customerFirstName,
        ]
        if let device = entry.deviceSummary {
            parts.append(device)
        }
        parts.append(entry.status.displayName)
        if isReady {
            parts.append("Ready for pickup")
        }
        return parts.joined(separator: ", ")
    }
}
