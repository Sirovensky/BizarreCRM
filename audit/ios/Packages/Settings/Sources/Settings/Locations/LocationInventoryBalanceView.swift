import SwiftUI
import Core
import DesignSystem

// MARK: - §60.2 LocationInventoryBalanceView

public struct LocationInventoryBalanceView: View {
    @State private var vm: LocationInventoryBalanceViewModel

    public init(repo: any LocationRepository, locations: [Location]) {
        _vm = State(initialValue: LocationInventoryBalanceViewModel(repo: repo, locations: locations))
    }

    public var body: some View {
        Group {
            if Platform.isCompact {
                iPhoneList
            } else {
                iPadGrid
            }
        }
        .navigationTitle("Inventory by Location")
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }

    // MARK: iPhone — grouped list

    @ViewBuilder
    private var iPhoneList: some View {
        List {
            ForEach(vm.skus, id: \.self) { sku in
                Section(sku) {
                    ForEach(vm.balances(for: sku)) { balance in
                        HStack {
                            Text(vm.locationName(for: balance.locationId))
                                .foregroundStyle(.bizarreOnSurface)
                            Spacer()
                            Text("\(balance.quantity)")
                                .font(.brandMono(size: 15))
                                .foregroundStyle(balance.isLow ? .bizarreError : .bizarreOnSurface)
                            if balance.isLow {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.bizarreWarning)
                                    .accessibilityLabel("Low stock")
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: iPad — Scrollable Grid (SKU rows × location columns)
    // Using Grid instead of Table because Table doesn't support dynamic column count
    // via ForEach in its column builder.

    @ViewBuilder
    private var iPadGrid: some View {
        ScrollView([.horizontal, .vertical]) {
            Grid(horizontalSpacing: DesignTokens.Spacing.lg, verticalSpacing: DesignTokens.Spacing.xs) {
                // Header row
                GridRow {
                    Text("SKU")
                        .font(.headline)
                        .frame(width: 140, alignment: .leading)
                    ForEach(vm.locations) { loc in
                        Text(loc.name)
                            .font(.headline)
                            .frame(width: 100)
                            .multilineTextAlignment(.center)
                    }
                }
                Divider()

                // Data rows
                ForEach(vm.skus, id: \.self) { sku in
                    GridRow {
                        Text(sku)
                            .font(.brandMono(size: 13))
                            .frame(width: 140, alignment: .leading)
                            .textSelection(.enabled)
                        ForEach(vm.locations) { loc in
                            let balance = vm.balance(for: sku, locationId: loc.id)
                            HStack(spacing: DesignTokens.Spacing.xxs) {
                                Text(balance.map { "\($0.quantity)" } ?? "—")
                                    .font(.brandMono(size: 13))
                                    .foregroundStyle(balance?.isLow == true ? .bizarreError : .bizarreOnSurface)
                                if balance?.isLow == true {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.bizarreWarning)
                                        .font(.caption)
                                        .accessibilityLabel("Low stock")
                                }
                            }
                            .frame(width: 100)
                        }
                    }
                }
            }
            .padding(DesignTokens.Spacing.lg)
        }
    }
}

// MARK: - ViewModel

@Observable
@MainActor
final class LocationInventoryBalanceViewModel {
    private(set) var balanceList: [LocationInventoryBalance] = []
    private(set) var locations: [Location]

    private let repo: any LocationRepository

    init(repo: any LocationRepository, locations: [Location]) {
        self.repo = repo
        self.locations = locations
    }

    var skus: [String] {
        Array(Set(balanceList.map(\.sku))).sorted()
    }

    func load() async {
        do {
            balanceList = try await repo.fetchInventoryBalances(locationId: nil)
        } catch {
            // Silently fail — caller shows stale data
        }
    }

    func balances(for sku: String) -> [LocationInventoryBalance] {
        balanceList.filter { $0.sku == sku }
    }

    func balance(for sku: String, locationId: String) -> LocationInventoryBalance? {
        balanceList.first(where: { $0.sku == sku && $0.locationId == locationId })
    }

    func locationName(for id: String) -> String {
        locations.first(where: { $0.id == id })?.name ?? id
    }
}
