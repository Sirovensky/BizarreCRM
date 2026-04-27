#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

/// §40.4 — Displays the local gift-card + store-credit audit trail.
///
/// Accessible from the GiftCardLookupView toolbar. Shows all recorded
/// operations in reverse-chronological order. Each row shows the kind
/// badge, card code (masked), amount, balance, and manager reference.
@MainActor
public struct GiftCardAuditLogView: View {

    @State private var entries: [GiftCardAuditLog.Entry] = []
    @Environment(\.dismiss) private var dismiss

    /// Optional filter to show only entries for a specific card code.
    public let cardCodeFilter: String?

    public init(cardCodeFilter: String? = nil) {
        self.cardCodeFilter = cardCodeFilter
    }

    public var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await loadEntries() }
    }

    // MARK: - Views

    private var navTitle: String {
        cardCodeFilter.map { "Audit — Card …\($0.suffix(4))" } ?? "Gift Card Audit Log"
    }

    private var emptyState: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 44))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("No audit entries")
                .font(.brandTitleLarge())
                .foregroundStyle(.bizarreOnSurface)
            Text("Gift card operations will appear here as they occur.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("giftCardAudit.empty")
    }

    private var list: some View {
        List {
            ForEach(entries) { entry in
                entryRow(entry)
                    .listRowBackground(Color.bizarreSurface1)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("giftCardAudit.list")
    }

    private func entryRow(_ entry: GiftCardAuditLog.Entry) -> some View {
        HStack(spacing: BrandSpacing.md) {
            // Kind badge
            Image(systemName: entry.kind.systemImage)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(kindColor(entry.kind))
                .frame(width: 36)
                .accessibilityHidden(true)

            // Details
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(entry.kind.displayName)
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
                Text("Card ···\(String(entry.cardCode.suffix(4)))")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                if let manager = entry.approvedByManagerId {
                    Label("Mgr: \(manager)", systemImage: "person.badge.key.fill")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                Text(Self.formatDate(entry.date))
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }

            Spacer(minLength: BrandSpacing.xs)

            // Amount + balance
            VStack(alignment: .trailing, spacing: BrandSpacing.xxs) {
                Text(amountLabel(entry))
                    .font(.brandTitleSmall())
                    .foregroundStyle(entry.amountCents >= 0 ? Color.bizarreSuccess : Color.bizarreError)
                    .monospacedDigit()
                if let balance = entry.balanceCents {
                    Text("Bal: \(CartMath.formatCents(balance))")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: entry))
    }

    // MARK: - Helpers

    private func kindColor(_ kind: GiftCardAuditLog.EntryKind) -> Color {
        switch kind {
        case .issued, .activated, .reloaded, .refunded: return .bizarreSuccess
        case .redeemed, .transferred:                   return .bizarreOrange
        case .voided:                                   return .bizarreError
        }
    }

    private func amountLabel(_ entry: GiftCardAuditLog.Entry) -> String {
        let formatted = CartMath.formatCents(abs(entry.amountCents))
        return entry.amountCents >= 0 ? "+\(formatted)" : "-\(formatted)"
    }

    private func accessibilityLabel(for entry: GiftCardAuditLog.Entry) -> String {
        "\(entry.kind.displayName). \(amountLabel(entry)). \(Self.formatDate(entry.date))."
    }

    private static func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f.string(from: date)
    }

    // MARK: - Data

    private func loadEntries() async {
        if let code = cardCodeFilter {
            entries = await GiftCardAuditLog.shared.entries(forCard: code)
        } else {
            entries = await GiftCardAuditLog.shared.allNewestFirst()
        }
    }
}
#endif
