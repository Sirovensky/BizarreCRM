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

    public init(
        revenueVM: RevenueSparklineViewModel,
        topSkusVM: TopSkusViewModel,
        topCustomersVM: TopCustomersViewModel,
        techLeaderboardVM: TechLeaderboardViewModel,
        openTicketsVM: OpenTicketsByStatusViewModel
    ) {
        self.revenueVM = revenueVM
        self.topSkusVM = topSkusVM
        self.topCustomersVM = topCustomersVM
        self.techLeaderboardVM = techLeaderboardVM
        self.openTicketsVM = openTicketsVM
    }

    public var body: some View {
        GeometryReader { geo in
            let columns = columnConfig(availableWidth: geo.size.width)
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    RevenueSparklineWidget(vm: revenueVM)
                    TopSkusWidget(vm: topSkusVM)
                    OpenTicketsByStatusWidget(vm: openTicketsVM)
                    TopCustomersWidget(vm: topCustomersVM)
                    TechLeaderboardWidget(vm: techLeaderboardVM)
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
        api: APIClient
    ) -> BIWidgetGridView {
        BIWidgetGridView(
            revenueVM:         RevenueSparklineViewModel(repo: repo),
            topSkusVM:         TopSkusViewModel(api: api),
            topCustomersVM:    TopCustomersViewModel(repo: repo),
            techLeaderboardVM: TechLeaderboardViewModel(repo: repo),
            openTicketsVM:     OpenTicketsByStatusViewModel(repo: repo)
        )
    }
}
