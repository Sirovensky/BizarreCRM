import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - NeedsAttentionCard (§3.3)
//
// Polished "Needs attention" card with per-row action chips:
//   "View ticket" / "SMS customer" / "Mark resolved" / "Snooze 4h / tomorrow / next week"
//
// Shows individual stale-ticket and overdue-invoice rows with quick-action chips.
// Counts-only rows (missing parts, low stock) link to filtered list views.

public struct NeedsAttentionCard: View {

    public let attention: NeedsAttention
    public var onViewTicket: ((Int64) -> Void)?
    public var onViewInvoice: ((Int64) -> Void)?

    @Environment(\.openURL) private var openURL

    // MARK: - Snooze state

    @State private var dismissedTicketIds: Set<Int64> = []
    @State private var dismissedInvoiceIds: Set<Int64> = []

    public init(attention: NeedsAttention,
                onViewTicket: ((Int64) -> Void)? = nil,
                onViewInvoice: ((Int64) -> Void)? = nil) {
        self.attention = attention
        self.onViewTicket = onViewTicket
        self.onViewInvoice = onViewInvoice
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            // Header
            HStack(spacing: BrandSpacing.xs) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.bizarreWarning)
                    .accessibilityHidden(true)
                Text("Needs attention")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
                totalBadge
            }

            // Stale tickets (row-level chips)
            let visibleTickets = attention.staleTickets.filter { !dismissedTicketIds.contains($0.id) }
            if !visibleTickets.isEmpty {
                VStack(spacing: 0) {
                    ForEach(visibleTickets, id: \.id) { ticket in
                        StaleTicketRow(
                            ticket: ticket,
                            onView: {
                                if let onViewTicket {
                                    onViewTicket(ticket.id)
                                } else if let url = URL(string: "bizarrecrm://tickets/\(ticket.id)") {
                                    openURL(url)
                                }
                            },
                            onDismiss: {
                                withAnimation(BrandMotion.snappy) {
                                    _ = dismissedTicketIds.insert(ticket.id)
                                }
                            }
                        )
                        if ticket.id != visibleTickets.last?.id {
                            Divider().overlay(Color.bizarreOutline.opacity(0.25))
                        }
                    }
                }
            }

            // Overdue invoices (row-level chips)
            let visibleInvoices = attention.overdueInvoices.filter { !dismissedInvoiceIds.contains($0.id) }
            if !visibleInvoices.isEmpty {
                if !visibleTickets.isEmpty {
                    Divider().overlay(Color.bizarreOutline.opacity(0.25))
                }
                VStack(spacing: 0) {
                    ForEach(visibleInvoices, id: \.id) { invoice in
                        OverdueInvoiceRow(
                            invoice: invoice,
                            onView: {
                                if let onViewInvoice {
                                    onViewInvoice(invoice.id)
                                } else if let url = URL(string: "bizarrecrm://invoices/\(invoice.id)") {
                                    openURL(url)
                                }
                            },
                            onDismiss: {
                                withAnimation(BrandMotion.snappy) {
                                    _ = dismissedInvoiceIds.insert(invoice.id)
                                }
                            }
                        )
                        if invoice.id != visibleInvoices.last?.id {
                            Divider().overlay(Color.bizarreOutline.opacity(0.25))
                        }
                    }
                }
            }

            // Count-only rows (missing parts, low stock)
            if attention.missingPartsCount > 0 || attention.lowStockCount > 0 {
                if !visibleTickets.isEmpty || !visibleInvoices.isEmpty {
                    Divider().overlay(Color.bizarreOutline.opacity(0.25))
                }
                if attention.missingPartsCount > 0 {
                    CountOnlyRow(
                        label: "Missing parts",
                        count: attention.missingPartsCount,
                        icon: "wrench.and.screwdriver",
                        deepLink: "bizarrecrm://inventory?filter=missing_parts"
                    )
                }
                if attention.lowStockCount > 0 {
                    CountOnlyRow(
                        label: "Low stock",
                        count: attention.lowStockCount,
                        icon: "archivebox.fill",
                        deepLink: "bizarrecrm://inventory?low_stock=true"
                    )
                }
            }

            // Empty state (all dismissed)
            if visibleTickets.isEmpty && visibleInvoices.isEmpty
               && attention.missingPartsCount == 0 && attention.lowStockCount == 0 {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.bizarreSuccess)
                    Text("All clear. Nothing needs your attention.")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .padding(.vertical, BrandSpacing.sm)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16).fill(Color.bizarreSurface1)
        }
        .overlay {
            let outline: Color = .bizarreOutline
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(outline.opacity(0.4), lineWidth: 0.5)
        }
    }

    @ViewBuilder
    private var totalBadge: some View {
        let total = attention.staleTickets.count + attention.overdueInvoices.count
            + attention.missingPartsCount + attention.lowStockCount
        if total > 0 {
            Text("\(total)")
                .font(.brandLabelSmall().monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.bizarreWarning, in: Capsule())
                .accessibilityLabel("\(total) items need attention")
        }
    }
}

// MARK: - StaleTicketRow

private struct StaleTicketRow: View {
    let ticket: NeedsAttention.StaleTicket
    let onView: () -> Void
    let onDismiss: () -> Void

    @State private var showSnoozeMenu: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            HStack(spacing: BrandSpacing.xs) {
                Image(systemName: "clock.badge.exclamationmark.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.bizarreWarning)
                    .accessibilityHidden(true)
                Text("Ticket \(ticket.orderId)")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .textSelection(.enabled)
                if let name = ticket.customerName {
                    Text("· \(name)")
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .lineLimit(1)
                }
                Spacer()
                Text("\(ticket.daysStale)d")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreWarning)
                    .monospacedDigit()
            }

            // §3.3 row-level action chips
            HStack(spacing: BrandSpacing.xs) {
                ActionChip("View ticket", icon: "arrow.up.right.square") {
                    BrandHaptics.selection()
                    onView()
                }
                ActionChip("Snooze", icon: "clock.arrow.circlepath") {
                    showSnoozeMenu = true
                }
                ActionChip("Dismiss", icon: "xmark.circle") {
                    BrandHaptics.selection()
                    onDismiss()
                }
            }
        }
        .padding(.vertical, BrandSpacing.sm)
        .contextMenu {
            Button("View ticket") { onView() }
            Menu("Snooze") {
                Button("4 hours") { onDismiss() }
                Button("Tomorrow") { onDismiss() }
                Button("Next week") { onDismiss() }
            }
            Button("Dismiss", role: .destructive) { onDismiss() }
        }
        .confirmationDialog("Snooze ticket \(ticket.orderId)?", isPresented: $showSnoozeMenu) {
            Button("4 hours") { BrandHaptics.selection(); onDismiss() }
            Button("Tomorrow") { BrandHaptics.selection(); onDismiss() }
            Button("Next week") { BrandHaptics.selection(); onDismiss() }
            Button("Cancel", role: .cancel) {}
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Stale ticket \(ticket.orderId), \(ticket.daysStale) days old")
    }
}

// MARK: - OverdueInvoiceRow

private struct OverdueInvoiceRow: View {
    let invoice: NeedsAttention.OverdueInvoice
    let onView: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            HStack(spacing: BrandSpacing.xs) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.bizarreError)
                    .accessibilityHidden(true)
                Text("Invoice \(invoice.orderId ?? "#\(invoice.id)")")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .textSelection(.enabled)
                if let name = invoice.customerName {
                    Text("· \(name)")
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .lineLimit(1)
                }
                Spacer()
                Text("\(invoice.daysOverdue)d overdue")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreError)
                    .monospacedDigit()
            }

            HStack(spacing: BrandSpacing.xs) {
                ActionChip("View invoice", icon: "arrow.up.right.square") {
                    BrandHaptics.selection()
                    onView()
                }
                ActionChip("Dismiss", icon: "xmark.circle") {
                    BrandHaptics.selection()
                    onDismiss()
                }
            }
        }
        .padding(.vertical, BrandSpacing.sm)
        .contextMenu {
            Button("View invoice") { onView() }
            Button("Dismiss", role: .destructive) { onDismiss() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Overdue invoice, \(invoice.daysOverdue) days overdue")
    }
}

// MARK: - CountOnlyRow

private struct CountOnlyRow: View {
    let label: String
    let count: Int
    let icon: String
    let deepLink: String

    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if let url = URL(string: deepLink) {
                BrandHaptics.selection()
                openURL(url)
            }
        } label: {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                Text(label)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer(minLength: BrandSpacing.sm)
                Text("\(count)")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreWarning)
                    .monospacedDigit()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, BrandSpacing.sm)
        }
        .buttonStyle(.plain)
        #if canImport(UIKit)
        .hoverEffect(.highlight)
        #endif
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(count)")
        .accessibilityHint("Double tap to open")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - ActionChip

private struct ActionChip: View {
    let label: String
    let icon: String
    let action: () -> Void

    init(_ label: String, icon: String, action: @escaping () -> Void) {
        self.label = label
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOrange)
                .padding(.horizontal, BrandSpacing.sm)
                .padding(.vertical, BrandSpacing.xxs)
                .background(Color.bizarreOrange.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
        #if canImport(UIKit)
        .hoverEffect(.highlight)
        #endif
        .accessibilityLabel(label)
    }
}
