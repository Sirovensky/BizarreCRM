import SwiftUI
import Core
import DesignSystem

// MARK: - ReferralLeaderboardViewModel

@Observable
@MainActor
public final class ReferralLeaderboardViewModel {
    public var entries: [ReferralLeaderEntry] = []
    public var isLoading = false
    public var errorMessage: String?

    private let service: ReferralService

    public init(service: ReferralService) {
        self.service = service
    }

    public func load() async {
        isLoading = true
        errorMessage = nil
        do {
            entries = try await service.fetchLeaderboard()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - ReferralLeaderboardView

/// Admin view: top-10 referrers with count + revenue generated.
public struct ReferralLeaderboardView: View {
    @State private var vm: ReferralLeaderboardViewModel

    public init(service: ReferralService) {
        _vm = State(initialValue: ReferralLeaderboardViewModel(service: service))
    }

    public var body: some View {
        Group {
            if vm.isLoading {
                ProgressView("Loading leaderboard…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Loading referral leaderboard")
            } else if let err = vm.errorMessage {
                ContentUnavailableView {
                    Label("Could Not Load", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(err)
                } actions: {
                    Button("Retry") { Task { await vm.load() } }
                        .buttonStyle(.brandGlass)
                }
            } else if vm.entries.isEmpty {
                ContentUnavailableView(
                    "No Referrals Yet",
                    systemImage: "person.2",
                    description: Text("Referral activity will appear here once customers start sharing their codes.")
                )
            } else {
                leaderboardContent
            }
        }
        .navigationTitle("Referral Leaderboard")
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }

    // MARK: - iPhone

    @ViewBuilder
    private var leaderboardContent: some View {
        if Platform.isCompact {
            iPhoneList
        } else {
            iPadTable
        }
    }

    private var iPhoneList: some View {
        List {
            ForEach(Array(vm.entries.prefix(10).enumerated()), id: \.element.id) { index, entry in
                LeaderboardRow(rank: index + 1, entry: entry)
                    .listRowBackground(Color.bizarreSurface1)
            }
        }
        .listStyle(.plain)
    }

    // MARK: - iPad Table

    @ViewBuilder
    private var iPadTable: some View {
        let ranked = vm.entries.prefix(10).enumerated().map { RankedEntry(rank: $0.offset + 1, entry: $0.element) }
        Table(ranked) {
            TableColumn("Rank") { item in
                Text("#\(item.rank)")
                    .font(.brandMono(size: 13))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .width(50)
            TableColumn("Customer") { item in
                Text(item.entry.customerName)
                    .font(.brandTitleSmall())
            }
            TableColumn("Referrals") { item in
                Text("\(item.entry.referralCount)")
                    .font(.brandBodyMedium())
                    .monospacedDigit()
            }
            .width(80)
            TableColumn("Revenue") { item in
                Text(centsFormatted(item.entry.revenueGeneratedCents))
                    .font(.brandBodyMedium())
                    .monospacedDigit()
                    .foregroundStyle(.bizarreSuccess)
            }
            .width(100)
        }
    }

    private func centsFormatted(_ cents: Int) -> String {
        let dollars = Double(cents) / 100
        return String(format: "$%.2f", dollars)
    }
}

// MARK: - LeaderboardRow (iPhone)

private struct LeaderboardRow: View {
    let rank: Int
    let entry: ReferralLeaderEntry

    var body: some View {
        HStack(spacing: BrandSpacing.md) {
            rankBadge
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(entry.customerName)
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
                Text("\(entry.referralCount) referral\(entry.referralCount == 1 ? "" : "s")")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer()
            Text(centsFormatted(entry.revenueGeneratedCents))
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreSuccess)
                .monospacedDigit()
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rank \(rank): \(entry.customerName), \(entry.referralCount) referrals, \(centsFormatted(entry.revenueGeneratedCents)) revenue")
    }

    private var rankBadge: some View {
        Text("#\(rank)")
            .font(.brandMono(size: 13))
            .foregroundStyle(rank <= 3 ? Color.bizarreOrange : Color.bizarreOnSurfaceMuted)
            .frame(width: 32, alignment: .center)
    }

    private func centsFormatted(_ cents: Int) -> String {
        String(format: "$%.2f", Double(cents) / 100)
    }
}

// MARK: - RankedEntry (Table helper)

private struct RankedEntry: Identifiable {
    let rank: Int
    let entry: ReferralLeaderEntry
    var id: String { entry.id }
}
