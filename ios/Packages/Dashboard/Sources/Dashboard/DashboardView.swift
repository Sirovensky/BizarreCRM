import SwiftUI
import Core
import DesignSystem
import Networking

public struct DashboardView: View {
    @State private var vm: DashboardViewModel

    public init(repo: DashboardRepository) {
        _vm = State(wrappedValue: DashboardViewModel(repo: repo))
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle("Dashboard")
                .navigationBarTitleDisplayMode(.inline)
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
            ErrorPane(message: message) {
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
            VStack(spacing: BrandSpacing.lg) {
                kpiGrid
                attentionCard
            }
            .padding(BrandSpacing.base)
        }
    }

    private var kpiGrid: some View {
        let s = snapshot.summary
        let cards: [KPI] = [
            KPI(label: "Open tickets",    value: "\(s.openTickets)",           icon: "wrench.and.screwdriver"),
            KPI(label: "Revenue today",   value: Self.money(s.revenueToday),   icon: "dollarsign.circle"),
            KPI(label: "Closed today",    value: "\(s.closedToday)",           icon: "checkmark.seal"),
            KPI(label: "New tickets",     value: "\(s.ticketsCreatedToday)",   icon: "plus.square"),
            KPI(label: "Appointments",    value: "\(s.appointmentsToday)",     icon: "calendar"),
            KPI(label: "Inventory value", value: Self.money(s.inventoryValue), icon: "shippingbox"),
        ]

        // Adaptive grid: iPhone gets ~2 columns (card ≥160pt), iPad/Mac
        // gets 3-4 columns automatically as window width grows. Max width
        // 1200 keeps cards readable on ultra-wide external displays.
        return LazyVGrid(
            columns: [
                GridItem(.adaptive(minimum: 160), spacing: BrandSpacing.md)
            ],
            spacing: BrandSpacing.md
        ) {
            ForEach(cards) { card in
                KPICard(kpi: card)
            }
        }
        .frame(maxWidth: 1200)
    }

    @ViewBuilder
    private var attentionCard: some View {
        let a = snapshot.attention
        let total = a.staleTickets.count + a.overdueInvoices.count + a.missingPartsCount + a.lowStockCount

        if total > 0 {
            VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                Text("Needs attention")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                row(icon: "clock.badge.exclamationmark", label: "Stale tickets",     count: a.staleTickets.count)
                row(icon: "doc.text",                    label: "Overdue invoices",  count: a.overdueInvoices.count)
                row(icon: "shippingbox.and.arrow.backward", label: "Missing parts",  count: a.missingPartsCount)
                row(icon: "exclamationmark.triangle",    label: "Low stock items",   count: a.lowStockCount)
            }
            .padding(BrandSpacing.base)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.bizarreOutline.opacity(0.5), lineWidth: 0.5)
            )
        }
    }

    private func row(icon: String, label: String, count: Int) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(count > 0 ? .bizarreWarning : .bizarreOnSurfaceMuted)
                .frame(width: 22)
            Text(label)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
            Spacer()
            Text("\(count)")
                .font(.brandTitleMedium())
                .foregroundStyle(count > 0 ? .bizarreWarning : .bizarreOnSurfaceMuted)
        }
        .padding(.vertical, BrandSpacing.xxs)
    }

    private static func money(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
    }
}

// MARK: - KPI card

private struct KPI: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    let icon: String
}

private struct KPICard: View {
    let kpi: KPI

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                Image(systemName: kpi.icon)
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityHidden(true)
                Spacer()
            }
            Text(kpi.value)
                .font(.brandHeadlineMedium())
                .foregroundStyle(.bizarreOnSurface)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .monospacedDigit()
            Text(kpi.label)
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .padding(BrandSpacing.base)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.bizarreOutline.opacity(0.5), lineWidth: 0.5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kpi.label)
        .accessibilityValue(kpi.value)
    }
}

// MARK: - Error pane

private struct ErrorPane: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.bizarreError)
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
