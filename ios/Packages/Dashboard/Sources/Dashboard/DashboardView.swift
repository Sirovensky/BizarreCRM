import SwiftUI
import Core
import DesignSystem
import Networking
#if canImport(UIKit)
import UIKit
#endif

public struct DashboardView: View {
    @State private var vm: DashboardViewModel

    public init(repo: DashboardRepository) {
        _vm = State(wrappedValue: DashboardViewModel(repo: repo))
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle("Dashboard")
                #if canImport(UIKit)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .refreshable { await vm.load() }
                .task { await vm.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        case .failed(let message):
            DashboardErrorPane(message: message) {
                Task { await vm.load() }
            }
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        case .loaded(let snapshot):
            LoadedBody(snapshot: snapshot)
                .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        }
    }
}

// MARK: - Loaded state

private struct LoadedBody: View {
    let snapshot: DashboardSnapshot

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                greeting
                heroCard
                secondaryGrid
                attentionCard
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.top, BrandSpacing.sm)
            .padding(.bottom, BrandSpacing.lg)
            .frame(maxWidth: 1200, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// §3.9 — dynamic greeting by hour. Reads the current locale's first
    /// day-part name, falls back to "Hello" if the clock lies. No server
    /// round trip; the user's first name would need `/auth/me` which is
    /// still TBD, so for now we keep it impersonal.
    private var greeting: some View {
        Text(Self.greetingText(for: Date()))
            .font(.brandTitleLarge())
            .foregroundStyle(.bizarreOnSurface)
            .accessibilityAddTraits(.isHeader)
    }

    static func greetingText(for date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default:      return "Working late"
        }
    }

    // Hero = the one primary focus. On a repair-shop dashboard that's
    // "open tickets right now". Larger, more visual weight than the rest.
    private var heroCard: some View {
        let s = snapshot.summary
        return HeroMetricCard(
            value: "\(s.openTickets)",
            label: "Open tickets",
            supporting: "\(s.ticketsCreatedToday) new today"
        )
    }

    // Compact stat tiles — muted hierarchy, 3 columns on iPhone, more on iPad.
    private var secondaryGrid: some View {
        let s = snapshot.summary
        let tiles: [StatTile] = [
            .init(label: "Revenue",     value: Self.money(s.revenueToday),    icon: "dollarsign.circle"),
            .init(label: "Closed",      value: "\(s.closedToday)",            icon: "checkmark.seal"),
            .init(label: "Appointments", value: "\(s.appointmentsToday)",     icon: "calendar"),
            .init(label: "Inventory",   value: Self.money(s.inventoryValue),  icon: "shippingbox"),
        ]

        return LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150), spacing: BrandSpacing.md)],
            spacing: BrandSpacing.md
        ) {
            ForEach(tiles) { tile in
                StatTileCard(tile: tile)
            }
        }
    }

    @ViewBuilder
    private var attentionCard: some View {
        let a = snapshot.attention
        let items: [AttentionItem] = [
            .init(label: "Stale tickets",    count: a.staleTickets.count),
            .init(label: "Overdue invoices", count: a.overdueInvoices.count),
            .init(label: "Missing parts",    count: a.missingPartsCount),
            .init(label: "Low stock",        count: a.lowStockCount),
        ]
        let total = items.reduce(0) { $0 + $1.count }

        if total > 0 {
            AttentionCard(items: items)
        }
    }

    private static func money(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
    }
}

// MARK: - Hero metric card

private struct HeroMetricCard: View {
    let value: String
    let label: String
    let supporting: String

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text(label.uppercased())
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .tracking(0.8)
            Text(value)
                .font(.brandDisplayMedium())
                .foregroundStyle(.bizarreOnSurface)
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(supporting)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .monospacedDigit()
        }
        .padding(BrandSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(value). \(supporting).")
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Stat tile

private struct StatTile: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    let icon: String
}

private struct StatTileCard: View {
    let tile: StatTile

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Image(systemName: tile.icon)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text(tile.value)
                .font(.brandTitleLarge())
                .foregroundStyle(.bizarreOnSurface)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(tile.label)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.bizarreOutline.opacity(0.35), lineWidth: 0.5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tile.label)
        .accessibilityValue(tile.value)
    }
}

// MARK: - Attention card

private struct AttentionItem: Identifiable {
    let id = UUID()
    let label: String
    let count: Int
}

private struct AttentionCard: View {
    let items: [AttentionItem]

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack(spacing: BrandSpacing.xs) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.bizarreWarning)
                    .accessibilityHidden(true)
                Text("Needs attention")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
            }

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                    AttentionRow(item: item)
                    if idx < items.count - 1 {
                        Divider()
                            .overlay(Color.bizarreOutline.opacity(0.25))
                    }
                }
            }
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
        )
    }
}

private struct AttentionRow: View {
    let item: AttentionItem

    var body: some View {
        HStack {
            Text(item.label)
                .font(.brandBodyMedium())
                .foregroundStyle(item.count > 0 ? .bizarreOnSurface : .bizarreOnSurfaceMuted)
            Spacer(minLength: BrandSpacing.sm)
            Text("\(item.count)")
                .font(.brandTitleSmall())
                .foregroundStyle(item.count > 0 ? .bizarreWarning : .bizarreOnSurfaceMuted)
                .monospacedDigit()
        }
        .padding(.vertical, BrandSpacing.sm)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.label)
        .accessibilityValue("\(item.count)")
        .contextMenu {
            #if canImport(UIKit)
            Button {
                UIPasteboard.general.string = "\(item.label): \(item.count)"
            } label: {
                Label("Copy '\(item.label): \(item.count)'", systemImage: "doc.on.doc")
            }
            #endif
        }
    }
}

// MARK: - Error pane

private struct DashboardErrorPane: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Couldn't load the dashboard")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text(message)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)
            Button("Try again", action: retry)
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
