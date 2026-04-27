import SwiftUI
import Observation
import Core
import DesignSystem
import Networking
import Sync

// MARK: - EstimateListViewModel

@MainActor
@Observable
public final class EstimateListViewModel {
    public private(set) var items: [Estimate] = []
    public private(set) var isLoading = false
    public private(set) var isLoadingMore = false
    public private(set) var errorMessage: String?
    public var searchQuery: String = ""
    public var statusFilter: EstimateStatusFilter = .all

    // §8.1 cursor pagination
    private var nextCursor: String?
    public private(set) var hasMore: Bool = false

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
        if resetCursor { nextCursor = nil; hasMore = false }
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
                let raw = result.value
                items = applyStatusFilter(raw)
                lastSyncedAt = result.lastSyncedAt
            } else {
                // Use cursor-aware path for status filtering
                let page = try await repo.listPage(
                    status: statusFilter,
                    keyword: searchQuery.isEmpty ? nil : searchQuery,
                    cursor: nil
                )
                items = page.estimates
                nextCursor = page.nextCursor
                hasMore = page.nextCursor != nil
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
    @State private var selected: Int64?
    @State private var showBulkConfirm: Bool = false
    @State private var pendingBulkAction: EstimateBulkAction?

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
            .toolbar {
                ToolbarItem(placement: .status) {
                    StalenessIndicator(lastSyncedAt: vm.lastSyncedAt)
                }
                ToolbarItem(placement: .primaryAction) {
                    if vm.isSelecting {
                        Button("Done") { vm.clearSelection() }
                    } else {
                        Button { withAnimation { vm.isSelecting = true } } label: {
                            Image(systemName: "checkmark.circle")
                        }
                        .accessibilityLabel("Select estimates")
                    }
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
            .toolbar {
                ToolbarItem(placement: .status) {
                    StalenessIndicator(lastSyncedAt: vm.lastSyncedAt)
                }
                ToolbarItem(placement: .primaryAction) {
                    if vm.isSelecting {
                        Menu {
                            Button("Select All") { vm.selectAll() }
                            Button("Clear Selection") { vm.clearSelection() }
                        } label: {
                            Image(systemName: "checklist")
                        }
                        .accessibilityLabel("Selection options")
                    } else {
                        Button { withAnimation { vm.isSelecting = true } } label: {
                            Image(systemName: "checkmark.circle")
                        }
                        .accessibilityLabel("Select estimates")
                        .keyboardShortcut("e", modifiers: [.command, .shift])
                    }
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
    private var contentView: some View {
        if vm.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage {
            EstimateErrorState(message: err) { Task { await vm.load() } }
        } else if vm.items.isEmpty && vm.isOffline {
            OfflineEmptyStateView(entityName: "estimates")
        } else if vm.items.isEmpty {
            EstimateEmptyState(filter: vm.statusFilter, keyword: vm.searchQuery)
        } else {
            ZStack(alignment: .bottom) {
                List {
                    ForEach(vm.items) { est in
                        Row(
                            estimate: est,
                            isSelected: vm.selectedIds.contains(est.id),
                            isSelecting: vm.isSelecting
                        ) {
                            if vm.isSelecting {
                                vm.toggleSelection(est.id)
                            } else {
                                selected = est.id
                            }
                        }
                        .listRowBackground(Color.bizarreSurface1)
                        .contextMenu { rowContextMenu(for: est) }
                        .onAppear {
                            if est.id == vm.items.last?.id {
                                Task { await vm.loadMore() }
                            }
                        }
                    }

                    if vm.isLoadingMore {
                        HStack {
                            Spacer()
                            ProgressView().padding(BrandSpacing.sm)
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                    }

                    if !vm.hasMore && !vm.items.isEmpty {
                        Text("End of list")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .frame(maxWidth: .infinity)
                            .padding(BrandSpacing.sm)
                            .listRowBackground(Color.clear)
                            .accessibilityLabel("End of estimates list")
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)

                // §8.1 Bulk action bar
                if vm.isSelecting && !vm.selectedIds.isEmpty {
                    BulkActionBar(
                        selectedCount: vm.selectedIds.count,
                        onSend: { pendingBulkAction = .send; showBulkConfirm = true },
                        onDelete: { pendingBulkAction = .delete; showBulkConfirm = true },
                        onExport: { pendingBulkAction = .export; showBulkConfirm = true },
                        onCancel: { vm.clearSelection() }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    // MARK: - Context menu (§8.1)

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
                    // §8 — order ID + version badge inline
                    HStack(spacing: BrandSpacing.xs) {
                        Text(estimate.orderId ?? "EST-?")
                            .font(.brandMono(size: 15))
                            .foregroundStyle(.bizarreOnSurface)
                            .textSelection(.enabled)
                        if let vn = estimate.versionNumber, vn > 1 {
                            Text("v\(vn)")
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.bizarreSurface2, in: Capsule())
                                .accessibilityLabel("Version \(vn)")
                        }
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

// MARK: - StatusTabChip

private struct StatusTabChip: View {
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

// MARK: - BulkActionBar (§8.1)

private struct BulkActionBar: View {
    let selectedCount: Int
    let onSend: () -> Void
    let onDelete: () -> Void
    let onExport: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: BrandSpacing.md) {
            Text("\(selectedCount) selected")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityLabel("\(selectedCount) estimates selected")

            Spacer()

            Button(action: onSend) {
                Image(systemName: "paperplane")
            }
            .accessibilityLabel("Send selected estimates")

            Button(action: onExport) {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel("Export selected estimates")

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .accessibilityLabel("Delete selected estimates")

            Button(action: onCancel) {
                Image(systemName: "xmark")
            }
            .accessibilityLabel("Cancel selection")
        }
        .padding(.horizontal, BrandSpacing.lg)
        .padding(.vertical, BrandSpacing.md)
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .padding(.horizontal, BrandSpacing.lg)
        .padding(.bottom, BrandSpacing.lg)
    }
}

// MARK: - PulseModifier (§8.1 expiring-soon chip)

private struct PulseModifier: ViewModifier {
    @State private var pulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(pulsing ? 0.4 : 1.0)
            .animation(
                .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                value: pulsing
            )
            .onAppear { pulsing = true }
    }
}

// MARK: - Empty / Error states

private struct EstimateErrorState: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Couldn't load estimates")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text(message)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
            Button("Try again", action: onRetry)
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct EstimateEmptyState: View {
    let filter: EstimateStatusFilter
    let keyword: String

    var body: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "list.clipboard")
                .font(.system(size: 48))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text(hint)
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, BrandSpacing.lg)
    }

    private var hint: String {
        if !keyword.isEmpty { return "No results for \"\(keyword)\"." }
        switch filter {
        case .all:       return "No estimates yet."
        case .draft:     return "No draft estimates."
        case .sent:      return "No estimates have been sent."
        case .approved:  return "No approved estimates."
        case .rejected:  return "No rejected estimates."
        case .expired:   return "No expired estimates."
        case .converted: return "No converted estimates."
        }
    }
}

// MARK: - Shared helpers

private func formatMoney(_ v: Double) -> String {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = "USD"
    return f.string(from: NSNumber(value: v)) ?? "$\(v)"
}
