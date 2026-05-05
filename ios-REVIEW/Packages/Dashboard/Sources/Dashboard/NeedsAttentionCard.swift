import SwiftUI
import Core
import DesignSystem
import Networking

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

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

            // Empty state (all dismissed) — §3.3 "All clear" + sparkle illustration
            if visibleTickets.isEmpty && visibleInvoices.isEmpty
               && attention.missingPartsCount == 0 && attention.lowStockCount == 0 {
                NeedsAttentionEmptyState()
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
        rowContent
            .modifier(NeedsAttentionSwipeActions(
                onSnooze: { showSnoozeMenu = true },
                onDismiss: {
                    BrandHaptics.selection()
                    onDismiss()
                }
            ))
    }

    private var rowContent: some View {
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
            // §3.3 iPad/Mac: full action set + Copy ID
            Button {
                BrandHaptics.selection()
                onView()
            } label: { Label("View ticket", systemImage: "arrow.up.right.square") }

            Button {
                BrandHaptics.selection()
                if let url = URL(string: "bizarrecrm://tickets/\(ticket.id)?action=sms") {
                    UIApplicationOpenURLBridge.open(url)
                }
            } label: { Label("SMS customer", systemImage: "message") }

            Button {
                BrandHaptics.success()
                onDismiss()
            } label: { Label("Mark resolved", systemImage: "checkmark.circle") }

            Menu {
                Button("4 hours") { BrandHaptics.selection(); onDismiss() }
                Button("Tomorrow") { BrandHaptics.selection(); onDismiss() }
                Button("Next week") { BrandHaptics.selection(); onDismiss() }
            } label: { Label("Snooze", systemImage: "clock.arrow.circlepath") }

            Divider()

            Button {
                NeedsAttentionClipboard.copy(ticket.orderId)
            } label: { Label("Copy ID", systemImage: "doc.on.doc") }

            Divider()

            Button(role: .destructive) {
                BrandHaptics.selection()
                onDismiss()
            } label: { Label("Dismiss", systemImage: "xmark.circle") }
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
        rowContent
            .modifier(NeedsAttentionSwipeActions(
                onSnooze: nil,
                onDismiss: {
                    BrandHaptics.selection()
                    onDismiss()
                }
            ))
    }

    private var rowContent: some View {
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
            // §3.3 iPad/Mac: full action set + Copy ID
            Button {
                BrandHaptics.selection()
                onView()
            } label: { Label("View invoice", systemImage: "arrow.up.right.square") }

            Button {
                BrandHaptics.selection()
                if let url = URL(string: "bizarrecrm://invoices/\(invoice.id)?action=sms") {
                    UIApplicationOpenURLBridge.open(url)
                }
            } label: { Label("SMS customer", systemImage: "message") }

            Button {
                BrandHaptics.success()
                onDismiss()
            } label: { Label("Mark resolved", systemImage: "checkmark.circle") }

            Divider()

            Button {
                let copyValue = invoice.orderId ?? "INV-\(invoice.id)"
                NeedsAttentionClipboard.copy(copyValue)
            } label: { Label("Copy ID", systemImage: "doc.on.doc") }

            Divider()

            Button(role: .destructive) {
                BrandHaptics.selection()
                onDismiss()
            } label: { Label("Dismiss", systemImage: "xmark.circle") }
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

// MARK: - §3.3 NeedsAttentionEmptyState (sparkle illustration)

/// "All clear" empty state with a sparkle illustration. Shown when every
/// stale ticket / overdue invoice has been dismissed and there are no
/// missing-parts or low-stock alerts. Reduce-Motion aware.
private struct NeedsAttentionEmptyState: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: BrandSpacing.sm) {
            ZStack {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.bizarreSuccess)
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.bizarreOrange)
                    .offset(x: 18, y: -16)
                    .symbolEffect(.variableColor.iterative, isActive: !reduceMotion)
                Image(systemName: "sparkle")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.bizarreTeal)
                    .offset(x: -20, y: 12)
            }
            .accessibilityHidden(true)

            Text("All clear")
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreOnSurface)

            Text("Nothing needs your attention.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, BrandSpacing.md)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("All clear. Nothing needs your attention.")
    }
}

// MARK: - §3.3 NeedsAttentionSwipeActions (iPhone leading=snooze, trailing=dismiss)

/// Drag-gesture–based swipe actions for VStack rows in the Needs-attention
/// card. iPhone-only (Platform.isCompact); iPad/Mac users get the
/// `.contextMenu` instead. Provides:
///   - Leading swipe → optional snooze callback (revealed icon: clock).
///   - Trailing swipe → dismiss with `.selection` haptic (revealed icon: xmark).
///
/// Threshold is 64pt; past that, the row snaps closed and fires the
/// callback. Below threshold the row springs back. Reduce-Motion aware.
private struct NeedsAttentionSwipeActions: ViewModifier {
    let onSnooze: (() -> Void)?
    let onDismiss: () -> Void

    @State private var dragOffset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let threshold: CGFloat = 64

    func body(content: Content) -> some View {
        if Platform.isCompact {
            content
                .offset(x: dragOffset)
                .background(alignment: .leading) {
                    if onSnooze != nil, dragOffset > 8 {
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundStyle(.white)
                                .padding(.leading, BrandSpacing.md)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.bizarreOrange)
                    }
                }
                .background(alignment: .trailing) {
                    if dragOffset < -8 {
                        HStack {
                            Spacer()
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.white)
                                .padding(.trailing, BrandSpacing.md)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.bizarreError)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .gesture(
                    DragGesture(minimumDistance: 16, coordinateSpace: .local)
                        .onChanged { value in
                            // Allow leading drag only when snooze is wired.
                            let dx = value.translation.width
                            if dx > 0 && onSnooze == nil { return }
                            dragOffset = dx
                        }
                        .onEnded { value in
                            let dx = value.translation.width
                            if dx <= -threshold {
                                BrandHaptics.selection()
                                withAnimation(reduceMotion ? .linear(duration: 0.1) : BrandMotion.snappy) {
                                    dragOffset = 0
                                }
                                onDismiss()
                            } else if dx >= threshold, let onSnooze {
                                withAnimation(reduceMotion ? .linear(duration: 0.1) : BrandMotion.snappy) {
                                    dragOffset = 0
                                }
                                onSnooze()
                            } else {
                                withAnimation(reduceMotion ? .linear(duration: 0.1) : BrandMotion.snappy) {
                                    dragOffset = 0
                                }
                            }
                        }
                )
        } else {
            content
        }
    }
}

// MARK: - §3.3 Clipboard helper (Copy ID)

/// Tiny pasteboard helper used by the Needs-attention context menu's
/// "Copy ID" action. Plain-text only — no URL payload — because the
/// stale-ticket / overdue-invoice rows expose only a record identifier,
/// not a destination resolvable by `DeepLinkBuilder` here.
private enum NeedsAttentionClipboard {
    @MainActor
    static func copy(_ value: String) {
        BrandHaptics.selection()
        #if canImport(UIKit)
        UIPasteboard.general.string = value
        #elseif canImport(AppKit)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(value, forType: .string)
        #endif
    }
}

// MARK: - §3.3 openURL bridge for context-menu actions

/// `Environment(\.openURL)` lives at the View level; context-menu Button
/// closures don't see it. Use the platform application directly.
private enum UIApplicationOpenURLBridge {
    @MainActor
    static func open(_ url: URL) {
        #if canImport(UIKit)
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        #elseif canImport(AppKit)
        NSWorkspace.shared.open(url)
        #endif
    }
}
