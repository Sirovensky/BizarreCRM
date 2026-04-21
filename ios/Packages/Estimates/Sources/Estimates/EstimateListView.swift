import SwiftUI
import Observation
import Core
import DesignSystem
import Networking
import Sync

@MainActor
@Observable
public final class EstimateListViewModel {
    public private(set) var items: [Estimate] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public var searchQuery: String = ""

    // Phase-3: staleness + offline
    public private(set) var lastSyncedAt: Date?
    public var isOffline: Bool = false

    @ObservationIgnored private let repo: EstimateRepository
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    public init(repo: EstimateRepository) { self.repo = repo }

    /// Legacy convenience init keeps existing call sites compiling.
    public init(api: APIClient) { self.repo = EstimateRepositoryImpl(api: api) }

    public func load() async {
        if items.isEmpty { isLoading = true }
        defer { isLoading = false }
        await fetch(forceRemote: false)
    }

    public func refresh() async {
        await fetch(forceRemote: true)
    }

    public func onSearchChange(_ q: String) {
        searchQuery = q
        searchTask?.cancel()
        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            await fetch(forceRemote: false)
        }
    }

    private func fetch(forceRemote: Bool) async {
        errorMessage = nil
        do {
            if let cached = repo as? EstimateCachedRepositoryImpl {
                let result: CachedResult<[Estimate]>
                if forceRemote {
                    result = try await cached.forceRefresh(
                        keyword: searchQuery.isEmpty ? nil : searchQuery
                    )
                } else {
                    result = try await cached.cachedList(
                        keyword: searchQuery.isEmpty ? nil : searchQuery
                    )
                }
                items = result.value
                lastSyncedAt = result.lastSyncedAt
            } else {
                items = try await repo.list(keyword: searchQuery.isEmpty ? nil : searchQuery)
            }
        } catch {
            AppLog.ui.error("Estimates load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}

public struct EstimateListView: View {
    @State private var vm: EstimateListViewModel
    @State private var searchText: String = ""

    public init(repo: EstimateRepository) { _vm = State(wrappedValue: EstimateListViewModel(repo: repo)) }

    /// Legacy convenience init keeps existing call sites compiling.
    public init(api: APIClient) { _vm = State(wrappedValue: EstimateListViewModel(api: api)) }

    public var body: some View {
        Group {
            if Platform.isCompact { compactLayout } else { regularLayout }
        }
        .task {
            vm.isOffline = !Reachability.shared.isOnline
            await vm.load()
        }
        .refreshable { await vm.refresh() }
    }

    private var compactLayout: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
                if vm.isOffline {
                    OfflineBanner(isOffline: true)
                        .padding(.top, BrandSpacing.xs)
                }
            }
            .navigationTitle("Estimates")
            .searchable(text: $searchText, prompt: "Search estimates")
            .onChange(of: searchText) { _, new in vm.onSearchChange(new) }
            .toolbar {
                ToolbarItem(placement: .status) {
                    StalenessIndicator(lastSyncedAt: vm.lastSyncedAt)
                }
            }
        }
    }

    private var regularLayout: some View {
        NavigationSplitView {
            ZStack(alignment: .top) {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
                if vm.isOffline {
                    OfflineBanner(isOffline: true)
                        .padding(.top, BrandSpacing.xs)
                }
            }
            .navigationTitle("Estimates")
            .searchable(text: $searchText, prompt: "Search estimates")
            .onChange(of: searchText) { _, new in vm.onSearchChange(new) }
            .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 520)
            .toolbar {
                ToolbarItem(placement: .status) {
                    StalenessIndicator(lastSyncedAt: vm.lastSyncedAt)
                }
            }
        } detail: {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: BrandSpacing.md) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 52))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityHidden(true)
                    Text("Select an estimate")
                        .font(.brandTitleMedium())
                        .foregroundStyle(.bizarreOnSurface)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("")
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage {
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 36)).foregroundStyle(.bizarreError)
                    .accessibilityHidden(true)
                Text("Couldn't load estimates").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
                Text(err).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted).multilineTextAlignment(.center)
                Button("Try again") { Task { await vm.load() } }.buttonStyle(.borderedProminent).tint(.bizarreOrange)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.items.isEmpty && vm.isOffline {
            OfflineEmptyStateView(entityName: "estimates")
        } else if vm.items.isEmpty {
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "list.clipboard").font(.system(size: 48)).foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                Text(searchText.isEmpty ? "No estimates" : "No results")
                    .font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(vm.items) { est in
                    Row(estimate: est).listRowBackground(Color.bizarreSurface1)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private struct Row: View {
        let estimate: Estimate

        var body: some View {
            HStack(alignment: .top, spacing: BrandSpacing.md) {
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(estimate.orderId ?? "EST-?")
                        .font(.brandMono(size: 15)).foregroundStyle(.bizarreOnSurface)
                        .textSelection(.enabled)
                    Text(estimate.customerName)
                        .font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurface).lineLimit(1)
                    if estimate.isExpiring == true, let days = estimate.daysUntilExpiry {
                        Text("Expires in \(days)d")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreWarning)
                    } else if let until = estimate.validUntil, !until.isEmpty {
                        Text("Valid until \(String(until.prefix(10)))")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: BrandSpacing.xxs) {
                    Text(formatMoney(estimate.total ?? 0))
                        .font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface).monospacedDigit()
                    if let status = estimate.status {
                        let statusLabel = status.capitalized
                        Text(statusLabel)
                            .font(.brandLabelSmall())
                            .padding(.horizontal, BrandSpacing.sm).padding(.vertical, BrandSpacing.xxs)
                            .foregroundStyle(.bizarreOnSurface)
                            .background(Color.bizarreSurface2, in: Capsule())
                            .accessibilityLabel("Status \(statusLabel)")
                    }
                }
            }
            .padding(.vertical, BrandSpacing.xs)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Self.a11y(for: estimate))
        }

        static func a11y(for est: Estimate) -> String {
            var parts: [String] = [est.orderId ?? "EST-?", est.customerName]
            parts.append(formatMoney(est.total ?? 0))
            if let status = est.status, !status.isEmpty { parts.append("Status \(status.capitalized)") }
            if est.isExpiring == true, let days = est.daysUntilExpiry {
                parts.append("Expires in \(days) days")
            } else if let until = est.validUntil, !until.isEmpty {
                parts.append("Valid until \(String(until.prefix(10)))")
            }
            return parts.joined(separator: ". ")
        }

        private static func formatMoney(_ v: Double) -> String {
            let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = "USD"
            return f.string(from: NSNumber(value: v)) ?? "$\(v)"
        }

        private func formatMoney(_ v: Double) -> String { Self.formatMoney(v) }
    }
}
