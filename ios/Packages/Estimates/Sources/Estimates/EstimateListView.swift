import SwiftUI
import Observation
import Core
import DesignSystem
import Networking
import Sync

// MARK: - §8.1 Estimate status filter

/// §8.1 Status tabs — All / Draft / Sent / Approved / Rejected / Expired / Converted.
public enum EstimateStatusFilter: String, CaseIterable, Sendable, Identifiable {
    case all, draft, sent, approved, rejected, expired, converted

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .all:       return "All"
        case .draft:     return "Draft"
        case .sent:      return "Sent"
        case .approved:  return "Approved"
        case .rejected:  return "Rejected"
        case .expired:   return "Expired"
        case .converted: return "Converted"
        }
    }

    public var serverValue: String? { self == .all ? nil : rawValue }
}

// MARK: - EstimateListViewModel

@MainActor
@Observable
public final class EstimateListViewModel {
    public private(set) var items: [Estimate] = []
    public private(set) var isLoading = false
    public private(set) var isLoadingMore = false
    public private(set) var errorMessage: String?
    public var searchQuery: String = ""
    /// §8.1 Active status tab.
    public var statusFilter: EstimateStatusFilter = .all
    /// §8.1 Active list filters (date range, customer, amount, validity).
    public var filters: EstimateListFilters = EstimateListFilters()
    // §8.1: Cursor-based pagination state
    private var nextCursor: String? = nil
    private var hasMore: Bool = false

    // Phase-3: staleness + offline
    public private(set) var lastSyncedAt: Date?
    public var isOffline: Bool = false

    // §8.1 multi-select / bulk
    public var selectedIds: Set<Int64> = []
    public var isSelecting: Bool = false
    public private(set) var bulkActionInProgress: Bool = false

    @ObservationIgnored private let repo: EstimateRepository
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    public init(repo: EstimateRepository) { self.repo = repo }

    /// Legacy convenience init keeps existing call sites compiling.
    public init(api: APIClient) { self.repo = EstimateRepositoryImpl(api: api) }

    // MARK: - §8.1 Cursor pagination

    /// Load the next page of estimates. No-op if already loading or no more pages.
    public func loadMoreIfNeeded() async {
        guard !isLoadingMore, hasMore, let cursor = nextCursor else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await repo.listPage(cursor: cursor, keyword: searchQuery.isEmpty ? nil : searchQuery, status: statusFilter.serverValue)
            items.append(contentsOf: page.estimates)
            nextCursor = page.nextCursor
            hasMore = page.hasMore
        } catch {
            AppLog.ui.warning("Estimates loadMore failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func load() async {
        if items.isEmpty { isLoading = true }
        defer { isLoading = false }
        await fetch(forceRemote: false, resetCursor: true)
    }

    public func refresh() async {
        await fetch(forceRemote: true, resetCursor: true)
    }

    public func applyStatusFilter(_ filter: EstimateStatusFilter) async {
        statusFilter = filter
        await fetch(forceRemote: true, resetCursor: true)
    }

    public func loadMore() async {
        guard hasMore, !isLoadingMore, let cursor = nextCursor else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await repo.listPage(
                status: statusFilter,
                keyword: searchQuery.isEmpty ? nil : searchQuery,
                cursor: cursor
            )
            items.append(contentsOf: page.estimates)
            nextCursor = page.nextCursor
            hasMore = page.nextCursor != nil
        } catch {
            AppLog.ui.error("Estimates load-more failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func applyStatusFilter(_ f: EstimateStatusFilter) async {
        statusFilter = f
        await fetch(forceRemote: false)
    }

    public func onSearchChange(_ q: String) {
        searchQuery = q
        searchTask?.cancel()
        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            await fetch(forceRemote: false, resetCursor: true)
        }
    }

    // MARK: - Bulk actions (§8.1)

    public func toggleSelection(_ id: Int64) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    public func selectAll() {
        selectedIds = Set(items.map(\.id))
    }

    public func clearSelection() {
        selectedIds = []
        isSelecting = false
    }

    // MARK: - Private

    private func fetch(forceRemote: Bool, resetCursor: Bool) async {
        errorMessage = nil
        // Reset cursor state on every fresh fetch.
        nextCursor = nil
        hasMore = false
        let keyword = searchQuery.isEmpty ? nil : searchQuery
        do {
            // §8.1: Try cursor-based pagination first page.
            do {
                let page = try await repo.listPage(cursor: nil, keyword: keyword, status: statusFilter.serverValue)
                items = page.estimates
                nextCursor = page.nextCursor
                hasMore = page.hasMore
                lastSyncedAt = Date()
                return
            } catch {
                // Cursor endpoint not yet supported — fall through to legacy path.
                AppLog.ui.warning("Cursor pagination unavailable, using legacy list: \(error.localizedDescription, privacy: .public)")
            }
            // Legacy path (in-memory cache or direct API)
            var all: [Estimate]
            if let cached = repo as? EstimateCachedRepositoryImpl {
                let result: CachedResult<[Estimate]>
                if forceRemote {
                    result = try await cached.forceRefresh(keyword: keyword)
                } else {
                    result = try await cached.cachedList(keyword: keyword)
                }
                all = result.value
                lastSyncedAt = result.lastSyncedAt
            } else {
                all = try await repo.list(keyword: keyword)
            }
            // §8.1: client-side status tab filter
            if let sv = statusFilter.serverValue {
                items = all.filter { ($0.status ?? "").lowercased() == sv }
            } else {
                items = all
            }
        } catch {
            AppLog.ui.error("Estimates load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    /// Local status filter applied when repo returns all (cached path).
    private func applyStatusFilter(_ all: [Estimate]) -> [Estimate] {
        guard statusFilter != .all else { return all }
        return all.filter { $0.status?.lowercased() == statusFilter.rawValue }
    }
}

// MARK: - EstimateListView

public struct EstimateListView: View {
    @State private var vm: EstimateListViewModel
    @State private var searchText: String = ""
    // §8.1 Filters sheet
    @State private var showFilters: Bool = false
    // §8.1 Bulk-action selection
    @State private var selectedIds: Set<Int64> = []
    @State private var editMode: EditMode = .inactive

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
        .sheet(isPresented: $showFilters) {
            EstimateListFiltersView(filters: $vm.filters)
                .onChange(of: vm.filters) { _, _ in
                    Task { await vm.load() }
                }
        }
    }

    // MARK: - iPhone layout

    private var compactLayout: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: 0) {
                    statusTabs
                    contentView
                }
                if vm.isOffline {
                    OfflineBanner(isOffline: true)
                        .padding(.top, BrandSpacing.xs)
                }
            }
            .navigationTitle("Estimates")
            .searchable(text: $searchText, prompt: "Search estimates")
            .onChange(of: searchText) { _, new in vm.onSearchChange(new) }
            .environment(\.editMode, $editMode)
            .toolbar {
                ToolbarItem(placement: .status) {
                    StalenessIndicator(lastSyncedAt: vm.lastSyncedAt)
                }
                // §8.1: Filter button with active-count badge
                ToolbarItem(placement: .topBarLeading) {
                    filterButton
                }
                // §8.1: Bulk select toggle
                ToolbarItem(placement: .primaryAction) {
                    Button(editMode.isEditing ? "Done" : "Select") {
                        withAnimation {
                            editMode = editMode.isEditing ? .inactive : .active
                            if !editMode.isEditing { selectedIds.removeAll() }
                        }
                    }
                    .accessibilityLabel(editMode.isEditing ? "Exit selection mode" : "Enter selection mode for bulk actions")
                }
            }
            // §8.1: Bulk-action bar shown when items are selected
            .safeAreaInset(edge: .bottom) {
                if editMode.isEditing && !selectedIds.isEmpty {
                    estimateBulkActionBar
                }
            }
        }
    }

    // MARK: - iPad layout

    private var regularLayout: some View {
        NavigationSplitView {
            ZStack(alignment: .top) {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: 0) {
                    statusTabs
                    contentView
                }
                if vm.isOffline {
                    OfflineBanner(isOffline: true)
                        .padding(.top, BrandSpacing.xs)
                }
            }
            .navigationTitle("Estimates")
            .searchable(text: $searchText, prompt: "Search estimates")
            .onChange(of: searchText) { _, new in vm.onSearchChange(new) }
            .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 520)
            .environment(\.editMode, $editMode)
            .toolbar {
                ToolbarItem(placement: .status) {
                    StalenessIndicator(lastSyncedAt: vm.lastSyncedAt)
                }
                ToolbarItem(placement: .topBarLeading) {
                    filterButton
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(editMode.isEditing ? "Done" : "Select") {
                        withAnimation {
                            editMode = editMode.isEditing ? .inactive : .active
                            if !editMode.isEditing { selectedIds.removeAll() }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if editMode.isEditing && !selectedIds.isEmpty {
                    estimateBulkActionBar
                }
            }
        } detail: {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                if let id = selected, let est = vm.items.first(where: { $0.id == id }) {
                    Text(est.orderId ?? "Estimate")
                        .font(.brandTitleMedium())
                        .foregroundStyle(.bizarreOnSurface)
                } else {
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
            }
            .navigationTitle("")
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: - Status tabs (§8.1)

    private var statusTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BrandSpacing.xs) {
                ForEach(EstimateStatusFilter.allCases, id: \.rawValue) { tab in
                    StatusTabChip(
                        label: tab.displayName,
                        selected: vm.statusFilter == tab
                    ) {
                        Task { await vm.applyStatusFilter(tab) }
                    }
                }
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.vertical, BrandSpacing.sm)
        }
        .scrollClipDisabled()
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            // §8.1 Status tabs chip row
            statusTabChips

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
                List(selection: $selectedIds) {
                    ForEach(vm.items) { est in
                        Row(estimate: est)
                            .listRowBackground(Color.bizarreSurface1)
                            .tag(est.id)
                            // §8.1: load-more trigger on last row
                            .onAppear {
                                if est.id == vm.items.last?.id {
                                    Task { await vm.loadMoreIfNeeded() }
                                }
                            }
                    }
                    // Loading-more indicator
                    if vm.isLoadingMore {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .accessibilityLabel("Loading more estimates")
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    // MARK: - Filter button

    private var filterButton: some View {
        Button {
            showFilters = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .accessibilityHidden(true)
                if vm.filters.activeCount > 0 {
                    Text("\(vm.filters.activeCount)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(Color.bizarreOrange, in: Circle())
                        .offset(x: 6, y: -6)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityLabel(vm.filters.activeCount > 0 ? "Filters (\(vm.filters.activeCount) active)" : "Filters")
        .accessibilityHint("Opens estimate filter options")
    }

    // MARK: - §8.1 Bulk action bar

    private var estimateBulkActionBar: some View {
        HStack(spacing: BrandSpacing.md) {
            Text("\(selectedIds.count) selected")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurface)
            Spacer()
            Button {
                // TODO: POST /api/v1/estimates/bulk-send when server endpoint ships
                AppLog.ui.info("Bulk send \(selectedIds.count) estimates — endpoint pending")
            } label: {
                Label("Send", systemImage: "paperplane")
            }
            .buttonStyle(.bordered)
            .disabled(selectedIds.isEmpty)
            .accessibilityLabel("Send selected estimates")

            Button(role: .destructive) {
                // TODO: DELETE /api/v1/estimates/bulk-delete when server endpoint ships
                AppLog.ui.info("Bulk delete \(selectedIds.count) estimates — endpoint pending")
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .disabled(selectedIds.isEmpty)
            .accessibilityLabel("Delete selected estimates")
        }
        .padding(BrandSpacing.md)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .padding(.horizontal, BrandSpacing.base)
        .padding(.bottom, BrandSpacing.sm)
    }

    /// §8.1 Status tab chips — All / Draft / Sent / Approved / Rejected / Expired / Converted.
    private var statusTabChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BrandSpacing.xs) {
                ForEach(EstimateStatusFilter.allCases) { tab in
                    EstimateStatusChip(
                        label: tab.displayName,
                        selected: vm.statusFilter == tab
                    ) {
                        Task { await vm.applyStatusFilter(tab) }
                    }
                }
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.vertical, BrandSpacing.sm)
        }
        .scrollClipDisabled()
    }

    private struct Row: View {
        let estimate: Estimate
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var pulsing: Bool = false

    @ViewBuilder
    private func rowContextMenu(for est: Estimate) -> some View {
        Button {
            selected = est.id
        } label: {
            Label("Open", systemImage: "doc")
        }
        Button {
            // §8.2 send — navigate to send sheet
            selected = est.id
        } label: {
            Label("Send", systemImage: "paperplane")
        }
        .disabled(est.status == "converted" || est.status == "approved")

        Button {
            // §4 convert to ticket flow
            selected = est.id
        } label: {
            Label("Convert to Ticket", systemImage: "wrench.and.screwdriver")
        }
        .disabled(est.status == "converted")

        Button {
            selected = est.id
        } label: {
            Label("Convert to Invoice", systemImage: "doc.text")
        }
        .disabled(est.status == "converted")

        Button {
            // Duplicate — re-creates via POST /estimates with prefilled fields
            // TODO: wire when Phase-4 duplicate endpoint available (§74 gap check)
        } label: {
            Label("Duplicate", systemImage: "doc.on.doc")
        }

        Divider()

        Button(role: .destructive) {
            // Delete — POST /estimates/:id delete
            // TODO: wire when confirmed in §74 audit
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}

// MARK: - Row

private struct Row: View {
    let estimate: Estimate
    let isSelected: Bool
    let isSelecting: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: BrandSpacing.md) {
                if isSelecting {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(isSelected ? Color.bizarreOrange : Color.bizarreOnSurfaceMuted)
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(estimate.orderId ?? "EST-?")
                        .font(.brandMono(size: 15)).foregroundStyle(.bizarreOnSurface)
                        .textSelection(.enabled)
                    Text(estimate.customerName)
                        .font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurface).lineLimit(1)
                    if estimate.isExpiring == true, let days = estimate.daysUntilExpiry {
                        // §8.1: pulse animation for ≤3 days remaining (respect Reduce Motion)
                        ExpiringChip(daysLeft: days, pulsing: pulsing)
                            .onAppear {
                                if days <= 3 && !reduceMotion {
                                    withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                                        pulsing = true
                                    }
                                }
                            }
                    } else if let until = estimate.validUntil, !until.isEmpty {
                        Text("Valid until \(String(until.prefix(10)))")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
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
                    if let status = estimate.status {
                        StatusPill(status.capitalized, hue: statusHue(status))
                    }
                }
            }
            .padding(.vertical, BrandSpacing.xs)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(EstimateListView.Row.a11y(for: estimate))
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    @ViewBuilder
    private var expiryLabel: some View {
        if estimate.isExpiring == true, let days = estimate.daysUntilExpiry {
            // §8.1 pulse animation when ≤ 3 days
            if days <= 3 {
                Text("Expires in \(days)d")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreWarning)
                    .modifier(PulseModifier())
            } else {
                Text("Expires in \(days)d")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreWarning)
            }
        } else if let until = estimate.validUntil, !until.isEmpty {
            Text("Valid until \(String(until.prefix(10)))")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    private func statusHue(_ status: String) -> StatusPill.Hue {
        switch status.lowercased() {
        case "approved": return .completed
        case "rejected", "expired": return .archived
        case "converted": return .inProgress
        case "sent": return .awaiting
        default: return .awaiting
        }
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
}

// MARK: - §8.1 Expiring-soon chip (pulse animation ≤3 days)

private struct ExpiringChip: View {
    let daysLeft: Int
    let pulsing: Bool

    var body: some View {
        HStack(spacing: BrandSpacing.xxs) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.system(size: 10, weight: .semibold))
                .accessibilityHidden(true)
            Text("Expires in \(daysLeft)d")
                .font(.brandLabelSmall())
        }
        .foregroundStyle(daysLeft <= 3 ? Color.bizarreError : Color.bizarreWarning)
        .padding(.horizontal, BrandSpacing.sm)
        .padding(.vertical, BrandSpacing.xxs)
        .background(
            (daysLeft <= 3 ? Color.bizarreError : Color.bizarreWarning).opacity(pulsing ? 0.2 : 0.08),
            in: Capsule()
        )
        .accessibilityLabel("Expires in \(daysLeft) day\(daysLeft == 1 ? "" : "s")")
    }
}

// MARK: - EstimateStatusChip

private struct EstimateStatusChip: View {
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.brandLabelLarge())
                .padding(.horizontal, BrandSpacing.md)
                .padding(.vertical, BrandSpacing.xs)
                .foregroundStyle(selected ? Color.black : Color.bizarreOnSurface)
                .background(
                    selected ? Color.bizarreOrange : Color.bizarreSurface1,
                    in: Capsule()
                )
                .overlay(
                    Capsule()
                        .strokeBorder(Color.bizarreOutline.opacity(selected ? 0 : 0.4), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}
