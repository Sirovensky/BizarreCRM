import SwiftUI
import Core
import DesignSystem
import Networking
import Sync

// MARK: - EstimatesThreeColumnView
//
// §22 iPad-only three-column layout:
//   Column 1 — status sidebar (filter chips + staleness)
//   Column 2 — estimate list (searchable, refreshable)
//   Column 3 — detail + preview inspector (EstimatePreviewInspector)
//
// Uses NavigationSplitView with .prominent style so all three columns are
// visible at once on 11-inch+ iPad.  Liquid Glass on navigation chrome only
// (per CLAUDE.md rules).  Context menus wired to EstimateContextMenu.

#if canImport(UIKit)

@MainActor
@Observable
public final class EstimatesThreeColumnViewModel {

    // MARK: - State

    public private(set) var items: [Estimate] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public var searchQuery: String = ""
    public private(set) var lastSyncedAt: Date?
    public var isOffline: Bool = false

    /// The currently selected status filter.  nil = All.
    public var selectedStatus: String? = nil

    /// The estimate selected in column 2.
    public var selectedEstimate: Estimate? = nil

    // MARK: - Available status filters

    public let statusFilters: [String?] = [nil, "draft", "sent", "approved", "signed", "converted", "rejected", "expired"]

    // MARK: - Dependencies

    @ObservationIgnored private let repo: EstimateRepository
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    // MARK: - Init

    public init(repo: EstimateRepository) {
        self.repo = repo
    }

    // MARK: - Actions

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
            guard !Task.isCancelled else { return }
            await fetch(forceRemote: false)
        }
    }

    // MARK: - Derived list

    public var filteredItems: [Estimate] {
        guard let status = selectedStatus else { return items }
        return items.filter { $0.status?.lowercased() == status }
    }

    // MARK: - Private

    private func fetch(forceRemote: Bool) async {
        errorMessage = nil
        do {
            if let cached = repo as? EstimateCachedRepositoryImpl {
                let result: CachedResult<[Estimate]>
                if forceRemote {
                    result = try await cached.forceRefresh(keyword: searchQuery.isEmpty ? nil : searchQuery)
                } else {
                    result = try await cached.cachedList(keyword: searchQuery.isEmpty ? nil : searchQuery)
                }
                items = result.value
                lastSyncedAt = result.lastSyncedAt
            } else {
                items = try await repo.list(keyword: searchQuery.isEmpty ? nil : searchQuery)
            }
        } catch {
            AppLog.ui.error("EstimatesThreeColumn load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - EstimatesThreeColumnView

public struct EstimatesThreeColumnView: View {

    @State private var vm: EstimatesThreeColumnViewModel
    @State private var searchText: String = ""
    private let api: APIClient
    private let onTicketCreated: @MainActor (Int64) -> Void

    public init(
        repo: EstimateRepository,
        api: APIClient,
        onTicketCreated: @escaping @MainActor (Int64) -> Void = { _ in }
    ) {
        _vm = State(wrappedValue: EstimatesThreeColumnViewModel(repo: repo))
        self.api = api
        self.onTicketCreated = onTicketCreated
    }

    public var body: some View {
        NavigationSplitView {
            statusSidebar
                .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 240)
        } content: {
            estimateList
                .navigationSplitViewColumnWidth(min: 280, ideal: 360, max: 480)
        } detail: {
            detailPane
        }
        .navigationSplitViewStyle(.prominentDetail)
        .task {
            vm.isOffline = !Reachability.shared.isOnline
            await vm.load()
        }
        .refreshable { await vm.refresh() }
    }

    // MARK: - Column 1: Status Sidebar

    private var statusSidebar: some View {
        ZStack(alignment: .top) {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                    Text("Filter")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .padding(.horizontal, BrandSpacing.md)
                        .padding(.top, BrandSpacing.md)
                        .accessibilityAddTraits(.isHeader)

                    ForEach(vm.statusFilters, id: \.self) { status in
                        StatusFilterChip(
                            label: status?.capitalized ?? "All",
                            isSelected: vm.selectedStatus == status,
                            count: countForStatus(status)
                        ) {
                            vm.selectedStatus = (vm.selectedStatus == status && status != nil) ? nil : status
                        }
                    }
                }
                .padding(.bottom, BrandSpacing.lg)
            }
        }
        .navigationTitle("Estimates")
        .toolbar {
            ToolbarItem(placement: .status) {
                StalenessIndicator(lastSyncedAt: vm.lastSyncedAt)
            }
        }
    }

    private func countForStatus(_ status: String?) -> Int {
        guard let status else { return vm.items.count }
        return vm.items.filter { $0.status?.lowercased() == status }.count
    }

    // MARK: - Column 2: Estimate List

    private var estimateList: some View {
        ZStack(alignment: .top) {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            listContent
            if vm.isOffline {
                OfflineBanner(isOffline: true)
                    .padding(.top, BrandSpacing.xs)
            }
        }
        .navigationTitle(vm.selectedStatus?.capitalized ?? "All")
        .searchable(text: $searchText, prompt: "Search estimates")
        .onChange(of: searchText) { _, new in vm.onSearchChange(new) }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    // ⌘N: handled via EstimateKeyboardShortcuts on the outer view
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New estimate")
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }

    @ViewBuilder
    private var listContent: some View {
        if vm.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage {
            errorState(err)
        } else if vm.filteredItems.isEmpty && vm.isOffline {
            OfflineEmptyStateView(entityName: "estimates")
        } else if vm.filteredItems.isEmpty {
            emptyState
        } else {
            List(selection: Binding(
                get: { vm.selectedEstimate?.id },
                set: { id in vm.selectedEstimate = vm.filteredItems.first { $0.id == id } }
            )) {
                ForEach(vm.filteredItems) { estimate in
                    EstimateListRowView(estimate: estimate)
                        .listRowBackground(Color.bizarreSurface1)
                        .hoverEffect(.highlight)
                        .contextMenu {
                            EstimateContextMenu(
                                estimate: estimate,
                                api: api,
                                onTicketCreated: onTicketCreated
                            )
                        }
                        .tag(estimate.id)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func errorState(_ err: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Couldn't load estimates")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text(err)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
            Button("Try again") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "list.clipboard")
                .font(.system(size: 48))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text(searchText.isEmpty ? "No estimates" : "No results")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Column 3: Detail + Preview Inspector

    @ViewBuilder
    private var detailPane: some View {
        if let estimate = vm.selectedEstimate {
            EstimatePreviewInspector(estimate: estimate, api: api, onTicketCreated: onTicketCreated)
                .id(estimate.id)
        } else {
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
                    Text("Choose from the list or press ⌘N to create a new estimate.")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("")
        }
    }
}

// MARK: - StatusFilterChip

private struct StatusFilterChip: View {
    let label: String
    let isSelected: Bool
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(.brandBodyMedium())
                    .foregroundStyle(isSelected ? .bizarreOrange : .bizarreOnSurface)
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(.brandLabelSmall())
                        .foregroundStyle(isSelected ? .bizarreOrange : .bizarreOnSurfaceMuted)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, BrandSpacing.md)
            .padding(.vertical, BrandSpacing.sm)
            .background(isSelected ? Color.bizarreOrange.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, BrandSpacing.xs)
        .accessibilityLabel("\(label), \(count) estimates\(isSelected ? ", selected" : "")")
    }
}

// MARK: - EstimateListRowView (shared compact row for column 2)

public struct EstimateListRowView: View {
    public let estimate: Estimate

    public init(estimate: Estimate) {
        self.estimate = estimate
    }

    public var body: some View {
        HStack(alignment: .top, spacing: BrandSpacing.md) {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(estimate.orderId ?? "EST-?")
                    .font(.brandMono(size: 15))
                    .foregroundStyle(.bizarreOnSurface)
                    .textSelection(.enabled)
                Text(estimate.customerName)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
                expiryLabel
            }
            Spacer()
            VStack(alignment: .trailing, spacing: BrandSpacing.xxs) {
                Text(formatMoney(estimate.total ?? 0))
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
                if let status = estimate.status, !status.isEmpty {
                    Text(status.capitalized)
                        .font(.brandLabelSmall())
                        .padding(.horizontal, BrandSpacing.sm)
                        .padding(.vertical, BrandSpacing.xxs)
                        .foregroundStyle(.bizarreOnSurface)
                        .background(Color.bizarreSurface2, in: Capsule())
                }
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a11yLabel)
    }

    @ViewBuilder
    private var expiryLabel: some View {
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

    private var a11yLabel: String {
        var parts: [String] = [estimate.orderId ?? "EST-?", estimate.customerName]
        parts.append(formatMoney(estimate.total ?? 0))
        if let status = estimate.status, !status.isEmpty { parts.append("Status \(status.capitalized)") }
        if estimate.isExpiring == true, let days = estimate.daysUntilExpiry {
            parts.append("Expires in \(days) days")
        }
        return parts.joined(separator: ". ")
    }

    private func formatMoney(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: v)) ?? "$\(v)"
    }
}

#endif // canImport(UIKit)
