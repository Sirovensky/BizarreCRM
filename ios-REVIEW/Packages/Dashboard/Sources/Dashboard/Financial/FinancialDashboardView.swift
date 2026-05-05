import SwiftUI
import Core
import DesignSystem
import Networking
#if canImport(UIKit)
import UIKit
#endif

// MARK: - FinancialDashboardView
//
// §59 Financial Dashboard — owner home screen surface.
//
// Layout contract (ios/CLAUDE.md):
//   iPad (regular): 3-column HStack — KPI row | top-customers list | cash-position card.
//   iPhone (compact): vertical ScrollView — KPI row, then customers list, then cash card.
//
// Liquid Glass: applied to the navigation toolbar chrome only (CLAUDE.md rules).
// No glass on list rows / data cards — content, not chrome.

public struct FinancialDashboardView: View {

    @State private var vm: FinancialDashboardViewModel

    public init(repo: FinancialDashboardRepository) {
        _vm = State(wrappedValue: FinancialDashboardViewModel(repo: repo))
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle("Financial Overview")
                #if canImport(UIKit)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        periodLabel
                            .padding(.horizontal, BrandSpacing.sm)
                            .padding(.vertical, 4)
                            .brandGlass(.clear, in: Capsule())
                    }
                }
                .refreshable { await vm.reload() }
                .task { await vm.load() }
        }
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
    }

    // MARK: - Content routing

    @ViewBuilder
    private var content: some View {
        switch vm.state {
        case .idle, .loading:
            loadingView
        case .failed(let message):
            errorView(message: message)
        case .loaded(let snapshot):
            LoadedContent(snapshot: snapshot, vm: vm)
        }
    }

    private var loadingView: some View {
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Couldn't load financial data")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text(message)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)
            Button("Try again") { Task { await vm.reload() } }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
    }

    private var periodLabel: some View {
        Text("\(vm.params.from) – \(vm.params.to)")
            .font(.brandLabelSmall())
            .foregroundStyle(.bizarreOnSurfaceMuted)
    }
}

// MARK: - Loaded content

private struct LoadedContent: View {
    let snapshot: FinancialDashboardSnapshot
    let vm: FinancialDashboardViewModel

    var body: some View {
        if Platform.isCompact {
            iPhoneLayout
        } else {
            iPadLayout
        }
    }

    // MARK: iPad — 3-column fixed layout

    private var iPadLayout: some View {
        HStack(alignment: .top, spacing: BrandSpacing.lg) {
            // Column 1: KPI metrics
            ScrollView {
                VStack(alignment: .leading, spacing: BrandSpacing.md) {
                    columnHeader("Key Metrics")
                    KPIColumn(snapshot: snapshot)
                }
                .padding(BrandSpacing.md)
            }
            .frame(minWidth: 220, maxWidth: 280)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Color.bizarreOutline.opacity(0.3), lineWidth: 0.5)
            )
            .hoverEffect(.highlight)

            // Column 2: Top customers list
            ScrollView {
                VStack(alignment: .leading, spacing: BrandSpacing.md) {
                    columnHeader("Top Customers")
                    TopCustomersColumn(customers: snapshot.topCustomers)
                }
                .padding(BrandSpacing.md)
            }
            .frame(minWidth: 240, maxWidth: .infinity)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Color.bizarreOutline.opacity(0.3), lineWidth: 0.5)
            )

            // Column 3: Cash position card
            ScrollView {
                VStack(alignment: .leading, spacing: BrandSpacing.md) {
                    columnHeader("Cash Position")
                    CashPositionColumn(cashPosition: snapshot.cashPosition)
                }
                .padding(BrandSpacing.md)
            }
            .frame(minWidth: 200, maxWidth: 260)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Color.bizarreOutline.opacity(0.3), lineWidth: 0.5)
            )
        }
        .padding(BrandSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
    }

    // MARK: iPhone — vertical scroll

    private var iPhoneLayout: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                sectionHeader("Key Metrics")
                KPIColumn(snapshot: snapshot)

                sectionHeader("Top Customers")
                TopCustomersColumn(customers: snapshot.topCustomers)

                sectionHeader("Cash Position")
                CashPositionColumn(cashPosition: snapshot.cashPosition)
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.vertical, BrandSpacing.md)
        }
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
    }

    private func columnHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.brandLabelSmall())
            .foregroundStyle(.bizarreOnSurfaceMuted)
            .tracking(0.8)
            .accessibilityAddTraits(.isHeader)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.brandTitleSmall())
            .foregroundStyle(.bizarreOnSurface)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - KPI column

/// Revenue, gross profit, net profit tiles.
private struct KPIColumn: View {
    let snapshot: FinancialDashboardSnapshot

    var body: some View {
        VStack(spacing: BrandSpacing.sm) {
            KPITile(
                label: "Net Revenue",
                value: financialFormatCurrency(snapshot.revenue.net),
                supporting: "Gross \(financialFormatCurrency(snapshot.revenue.gross))",
                icon: "dollarsign.circle"
            )
            KPITile(
                label: "Gross Profit",
                value: financialFormatCurrency(snapshot.grossProfit.value),
                supporting: financialFormatPercent(snapshot.grossProfit.marginPct) + " margin",
                icon: "chart.line.uptrend.xyaxis"
            )
            KPITile(
                label: "Net Profit",
                value: financialFormatCurrency(snapshot.netProfit.value),
                supporting: financialFormatPercent(snapshot.netProfit.marginPct) + " margin",
                icon: "banknote",
                isHighlighted: snapshot.netProfit.value < 0
            )
            if snapshot.revenue.refunds > 0 || snapshot.revenue.discounts > 0 {
                KPITile(
                    label: "Refunds + Discounts",
                    value: financialFormatCurrency(snapshot.revenue.refunds + snapshot.revenue.discounts),
                    supporting: "Refunds \(financialFormatCurrency(snapshot.revenue.refunds))",
                    icon: "arrow.uturn.backward.circle",
                    isHighlighted: false
                )
            }
        }
    }
}

private struct KPITile: View {
    let label: String
    let value: String
    let supporting: String
    let icon: String
    var isHighlighted: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: BrandSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(isHighlighted ? Color.bizarreError : Color.bizarreOnSurfaceMuted)
                .frame(width: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Text(value)
                    .font(.brandTitleMedium())
                    .foregroundStyle(isHighlighted ? Color.bizarreError : Color.bizarreOnSurface)
                    .monospacedDigit()
                Text(supporting)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreSurface2, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.bizarreOutline.opacity(0.3), lineWidth: 0.5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(value). \(supporting).")
    }
}

// MARK: - Top customers column

private struct TopCustomersColumn: View {
    let customers: [FinancialTopCustomer]

    var body: some View {
        if customers.isEmpty {
            Text("No customer data for this period.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, BrandSpacing.sm)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(customers.enumerated()), id: \.element.id) { idx, customer in
                    TopCustomerRow(rank: idx + 1, customer: customer)
                    if idx < customers.count - 1 {
                        Divider()
                            .overlay(Color.bizarreOutline.opacity(0.2))
                    }
                }
            }
            .background(Color.bizarreSurface2, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.bizarreOutline.opacity(0.3), lineWidth: 0.5)
            )
        }
    }
}

private struct TopCustomerRow: View {
    let rank: Int
    let customer: FinancialTopCustomer

    var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            Text("\(rank)")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .monospacedDigit()
                .frame(width: 20, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(customer.name)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
                Text(financialFormatCurrency(customer.revenue))
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .monospacedDigit()
            }

            Spacer(minLength: BrandSpacing.sm)

            Text(financialFormatCurrency(customer.revenue))
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreOnSurface)
                .monospacedDigit()
        }
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.sm)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rank \(rank): \(customer.name)")
        .accessibilityValue(financialFormatCurrency(customer.revenue))
        #if canImport(UIKit)
        .contextMenu {
            Button {
                UIPasteboard.general.string = "\(customer.name): \(financialFormatCurrency(customer.revenue))"
            } label: {
                Label("Copy '\(customer.name)'", systemImage: "doc.on.doc")
            }
        }
        #endif
    }
}

// MARK: - Cash position column

private struct CashPositionColumn: View {
    let cashPosition: FinancialCashPosition

    var body: some View {
        VStack(spacing: BrandSpacing.sm) {
            CashTile(
                label: "Outstanding AR",
                value: financialFormatCurrency(cashPosition.outstanding),
                icon: "clock.badge.questionmark",
                isWarning: false
            )
            CashTile(
                label: "Overdue",
                value: financialFormatCurrency(cashPosition.overdue),
                icon: "exclamationmark.circle",
                isWarning: cashPosition.overdue > 0
            )

            if cashPosition.isApproximate {
                HStack(spacing: BrandSpacing.xs) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityHidden(true)
                    Text("Values are approximate (large dataset)")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .padding(.top, BrandSpacing.xs)
            }
        }
    }
}

private struct CashTile: View {
    let label: String
    let value: String
    let icon: String
    let isWarning: Bool

    var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(isWarning ? Color.bizarreWarning : Color.bizarreOnSurfaceMuted)
                .frame(width: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Text(value)
                    .font(.brandTitleMedium())
                    .foregroundStyle(isWarning ? Color.bizarreWarning : Color.bizarreOnSurface)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreSurface2, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isWarning ? Color.bizarreWarning.opacity(0.4) : Color.bizarreOutline.opacity(0.3),
                    lineWidth: 0.5
                )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}
