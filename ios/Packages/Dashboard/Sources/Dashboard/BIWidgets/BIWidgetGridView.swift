import SwiftUI
import Core
import Networking

// MARK: - BIWidgetGridView
//
// Responsive grid container for all §3.2 BI widgets.
//
// Layout (CLAUDE.md + §3.2 spec):
//   iPhone (compact)  → 1 column
//   iPad ≥ 600pt      → 3 columns (fixed)
//   Mac (Designed for iPad) → 3 columns, capped at 1200pt

public struct BIWidgetGridView: View {
    private let revenueVM: RevenueSparklineViewModel
    private let topSkusVM: TopSkusViewModel
    private let topCustomersVM: TopCustomersViewModel
    private let techLeaderboardVM: TechLeaderboardViewModel
    private let openTicketsVM: OpenTicketsByStatusViewModel
    // §3.2 new widgets
    private let busyHoursVM: BusyHoursViewModel
    private let cashTrappedVM: CashTrappedViewModel
    private let churnAlertVM: ChurnAlertViewModel
    private let forecastVM: ForecastViewModel
    private let missingPartsVM: MissingPartsViewModel
    /// Called when user taps Cash-Trapped card (→ Aging report).
    public var onTapAgingReport: (() -> Void)?
    /// Called when user taps Churn Alert card (→ Customers filtered `churn_risk`).
    public var onTapChurnList: (() -> Void)?
    /// Called when user taps Missing Parts card (→ Inventory filtered).
    public var onTapMissingPartsInventory: (() -> Void)?

    public init(
        revenueVM: RevenueSparklineViewModel,
        topSkusVM: TopSkusViewModel,
        topCustomersVM: TopCustomersViewModel,
        techLeaderboardVM: TechLeaderboardViewModel,
        openTicketsVM: OpenTicketsByStatusViewModel,
        busyHoursVM: BusyHoursViewModel,
        cashTrappedVM: CashTrappedViewModel,
        churnAlertVM: ChurnAlertViewModel,
        forecastVM: ForecastViewModel,
        missingPartsVM: MissingPartsViewModel,
        onTapAgingReport: (() -> Void)? = nil,
        onTapChurnList: (() -> Void)? = nil,
        onTapMissingPartsInventory: (() -> Void)? = nil
    ) {
        self.revenueVM = revenueVM
        self.topSkusVM = topSkusVM
        self.topCustomersVM = topCustomersVM
        self.techLeaderboardVM = techLeaderboardVM
        self.openTicketsVM = openTicketsVM
        self.busyHoursVM = busyHoursVM
        self.cashTrappedVM = cashTrappedVM
        self.churnAlertVM = churnAlertVM
        self.forecastVM = forecastVM
        self.missingPartsVM = missingPartsVM
        self.onTapAgingReport = onTapAgingReport
        self.onTapChurnList = onTapChurnList
        self.onTapMissingPartsInventory = onTapMissingPartsInventory
    }

    public var body: some View {
        GeometryReader { geo in
            let columns = columnConfig(availableWidth: geo.size.width)
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    // Row 1 — revenue + status + tech
                    RevenueSparklineWidget(vm: revenueVM)
                    OpenTicketsByStatusWidget(vm: openTicketsVM)
                    TechLeaderboardWidget(vm: techLeaderboardVM)
                    // Row 2 — customers + SKUs + busy hours
                    TopCustomersWidget(vm: topCustomersVM)
                    TopSkusWidget(vm: topSkusVM)
                    BusyHoursHeatmapWidget(vm: busyHoursVM)
                    // Row 3 — financial health
                    ForecastWidget(vm: forecastVM)
                    CashTrappedWidget(vm: cashTrappedVM, onTapAgingReport: onTapAgingReport)
                    ChurnAlertWidget(vm: churnAlertVM, onTapChurnList: onTapChurnList)
                    // Row 4 — operational alerts
                    MissingPartsAlertWidget(vm: missingPartsVM, onTapInventory: onTapMissingPartsInventory)
                }
                .padding(16)
                .frame(maxWidth: 1200, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func columnConfig(availableWidth: CGFloat) -> [GridItem] {
        if Platform.isCompact || availableWidth < 600 {
            return [GridItem(.flexible(), spacing: 16)]
        }
        return [
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16),
        ]
    }
}

// MARK: - Factory

extension BIWidgetGridView {
    public static func makeDefault(
        repo: DashboardBIRepository,
        api: APIClient,
        onTapAgingReport: (() -> Void)? = nil,
        onTapChurnList: (() -> Void)? = nil,
        onTapMissingPartsInventory: (() -> Void)? = nil
    ) -> BIWidgetGridView {
        BIWidgetGridView(
            revenueVM:         RevenueSparklineViewModel(repo: repo),
            topSkusVM:         TopSkusViewModel(api: api),
            topCustomersVM:    TopCustomersViewModel(repo: repo),
            techLeaderboardVM: TechLeaderboardViewModel(repo: repo),
            openTicketsVM:     OpenTicketsByStatusViewModel(repo: repo),
            busyHoursVM:       BusyHoursViewModel(repo: repo),
            cashTrappedVM:     CashTrappedViewModel(repo: repo),
            churnAlertVM:      ChurnAlertViewModel(repo: repo),
            forecastVM:        ForecastViewModel(repo: repo),
            missingPartsVM:    MissingPartsViewModel(repo: repo),
            onTapAgingReport:             onTapAgingReport,
            onTapChurnList:               onTapChurnList,
            onTapMissingPartsInventory:   onTapMissingPartsInventory
        )
    }
}
