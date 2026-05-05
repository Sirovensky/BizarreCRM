import SwiftUI
import Observation
import DesignSystem

// MARK: - §3 Leaderboard Preview Card
//
// Compact 3-row preview of the tech leaderboard on the main dashboard.
// Reuses TechLeaderboardViewModel + DashboardBIRepository — no new network
// contract needed. Tap row or "See all" → deep link to full leaderboard.
//
// Skips TV board (§3.13) per spec.

public struct LeaderboardPreviewCard: View {
    @State private var vm: TechLeaderboardViewModel
    /// Called when the user taps "See all" or any row. App layer navigates to
    /// the full TechLeaderboardWidget / BI grid.
    public var onSeeAll: (() -> Void)?

    public init(vm: TechLeaderboardViewModel, onSeeAll: (() -> Void)? = nil) {
        _vm = State(wrappedValue: vm)
        self.onSeeAll = onSeeAll
    }

    public var body: some View {
        BIWidgetChrome(title: "Leaderboard", systemImage: "trophy") {
            switch vm.state {
            case .idle:
                EmptyView()
            case .loading:
                BIWidgetLoadingOverlay()
            case .loaded(let payload):
                if payload.leaderboard.isEmpty {
                    BIWidgetEmptyState(message: "No data yet for this period.")
                } else {
                    PreviewContent(
                        entries: Array(payload.leaderboard.prefix(3)),
                        onSeeAll: onSeeAll
                    )
                }
            case .failed(let msg):
                BIWidgetErrorState(message: msg) {
                    Task { await vm.reload() }
                }
            }
        }
        .task { await vm.load() }
        .accessibilityLabel("Leaderboard preview")
    }
}

// MARK: - PreviewContent

private struct PreviewContent: View {
    let entries: [TechLeaderboardEntry]
    var onSeeAll: (() -> Void)?

    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f
    }()

    private func revenueString(_ value: Double) -> String {
        Self.currencyFormatter.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { idx, entry in
                Button {
                    onSeeAll?()
                } label: {
                    HStack(spacing: 8) {
                        // Rank badge
                        Text("\(idx + 1)")
                            .font(.brandLabelSmall())
                            .foregroundStyle(rankColor(for: idx + 1))
                            .frame(width: 16, alignment: .trailing)
                            .monospacedDigit()

                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.name)
                                .font(.brandBodyMedium())
                                .foregroundStyle(.bizarreOnSurface)
                                .lineLimit(1)
                            Text("\(entry.ticketsClosed) closed")
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        }

                        Spacer(minLength: 4)

                        Text(revenueString(entry.revenue))
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurface)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                #if canImport(UIKit)
                .hoverEffect(.highlight)
                #endif
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(idx + 1). \(entry.name). \(revenueString(entry.revenue)), \(entry.ticketsClosed) tickets closed.")

                if idx < entries.count - 1 {
                    Divider().overlay(Color.bizarreOutline.opacity(0.2))
                }
            }

            if onSeeAll != nil {
                Divider()
                    .overlay(Color.bizarreOutline.opacity(0.2))
                    .padding(.top, 2)

                Button(action: { onSeeAll?() }) {
                    HStack {
                        Spacer(minLength: 0)
                        Text("See full leaderboard")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOrange)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.bizarreOrange)
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("See full leaderboard")
            }
        }
    }

    private func rankColor(for rank: Int) -> Color {
        switch rank {
        case 1: return Color(.systemYellow)
        case 2: return Color(.systemGray)
        case 3: return Color(.systemOrange)
        default: return .bizarreOnSurfaceMuted
        }
    }
}
