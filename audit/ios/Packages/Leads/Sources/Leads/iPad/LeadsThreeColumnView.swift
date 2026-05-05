import SwiftUI
import Observation
import Core
import DesignSystem
import Networking
import Sync

// MARK: - LeadsThreeColumnViewModel

/// Drives the three-column iPad layout: sidebar filter → lead list → detail.
@MainActor
@Observable
public final class LeadsThreeColumnViewModel {

    // MARK: - State

    public private(set) var leads: [Lead] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public var searchQuery: String = ""
    public var selectedLeadId: Int64? = nil
    public private(set) var lastSyncedAt: Date?

    // MARK: - Sidebar

    public let sidebar: LeadPipelineSidebarViewModel

    // MARK: - Private

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let cachedRepo: LeadCachedRepository?
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    public init(api: APIClient, cachedRepo: LeadCachedRepository? = nil) {
        self.api = api
        self.cachedRepo = cachedRepo
        self.sidebar = LeadPipelineSidebarViewModel()
    }

    // MARK: - Derived

    /// Leads filtered by the sidebar status selection and the search query.
    public var filteredLeads: [Lead] {
        let byStatus: [Lead]
        if let selected = sidebar.selectedStatus {
            byStatus = leads.filter {
                LeadPipelineSidebarStatus.from(status: $0.status) == selected
            }
        } else {
            byStatus = leads
        }
        guard !searchQuery.isEmpty else { return byStatus }
        let q = searchQuery.lowercased()
        return byStatus.filter {
            $0.displayName.lowercased().contains(q)
            || ($0.email?.lowercased().contains(q) ?? false)
            || ($0.phone?.contains(q) ?? false)
            || ($0.orderId?.lowercased().contains(q) ?? false)
        }
    }

    // MARK: - Load

    public func load() async {
        if leads.isEmpty { isLoading = true }
        defer { isLoading = false }
        errorMessage = nil
        do {
            let keyword: String? = searchQuery.isEmpty ? nil : searchQuery
            let fresh: [Lead]
            if let repo = cachedRepo {
                fresh = try await repo.listLeads(keyword: keyword)
                lastSyncedAt = await repo.lastSyncedAt
            } else {
                fresh = try await api.listLeads(keyword: keyword)
            }
            leads = fresh
            sidebar.updateCounts(from: fresh)
        } catch {
            AppLog.ui.error("LeadsThreeColumn load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    public func forceRefresh() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            let keyword: String? = searchQuery.isEmpty ? nil : searchQuery
            let fresh: [Lead]
            if let repo = cachedRepo {
                fresh = try await repo.forceRefresh(keyword: keyword)
                lastSyncedAt = await repo.lastSyncedAt
            } else {
                fresh = try await api.listLeads(keyword: keyword)
            }
            leads = fresh
            sidebar.updateCounts(from: fresh)
        } catch {
            AppLog.ui.error("LeadsThreeColumn refresh failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    public func onSearchChange(_ q: String) {
        searchQuery = q
        searchTask?.cancel()
        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            await load()
        }
    }

    // MARK: - Keyboard navigation

    public func selectNext() {
        let items = filteredLeads
        guard !items.isEmpty else { return }
        if let current = selectedLeadId,
           let idx = items.firstIndex(where: { $0.id == current }),
           idx + 1 < items.count {
            selectedLeadId = items[idx + 1].id
        } else if selectedLeadId == nil {
            selectedLeadId = items.first?.id
        }
    }

    public func selectPrevious() {
        let items = filteredLeads
        guard !items.isEmpty else { return }
        if let current = selectedLeadId,
           let idx = items.firstIndex(where: { $0.id == current }),
           idx > 0 {
            selectedLeadId = items[idx - 1].id
        }
    }

    // MARK: - Context menu actions

    public func handleContextAction(_ action: LeadContextMenuAction, for lead: Lead) async {
        switch action {
        case .convertToCustomer:
            do {
                let body = LeadConvertBody(createTicket: false)
                _ = try await api.convertLead(id: lead.id, body: body)
                await load()
            } catch {
                AppLog.ui.error("Convert failed: \(error.localizedDescription, privacy: .public)")
                errorMessage = error.localizedDescription
            }
        case .changeStatus(let newStatus):
            do {
                let body = LeadStatusUpdateBody(status: newStatus)
                _ = try await api.updateLeadStatus(id: lead.id, body: body)
                await load()
            } catch {
                AppLog.ui.error("Status change failed: \(error.localizedDescription, privacy: .public)")
                errorMessage = error.localizedDescription
            }
        case .archive:
            do {
                let body = LeadLoseBody(reason: "other", notes: "Archived from lead list")
                _ = try await api.loseLead(id: lead.id, body: body)
                if selectedLeadId == lead.id { selectedLeadId = nil }
                await load()
            } catch {
                AppLog.ui.error("Archive failed: \(error.localizedDescription, privacy: .public)")
                errorMessage = error.localizedDescription
            }
        case .assign:
            // Assignment requires a picker sheet — signal via selectedLeadId
            // so the view can present the AssignSheet. No API call here.
            selectedLeadId = lead.id
        }
    }
}

// MARK: - LeadsThreeColumnView

/// iPad-exclusive three-column `NavigationSplitView` for the Leads module.
///
/// Column 1 — Status pipeline sidebar with counts (LeadPipelineSidebar).
/// Column 2 — Filtered lead list.
/// Column 3 — Lead detail.
///
/// Only rendered when `!Platform.isCompact`. The compact (iPhone) layout falls
/// back to the existing `LeadListView`.
public struct LeadsThreeColumnView: View {

    @State private var vm: LeadsThreeColumnViewModel
    @State private var searchText: String = ""
    @State private var showingCreate = false
    @State private var showingAssign = false
    private let api: APIClient

    public init(api: APIClient, cachedRepo: LeadCachedRepository? = nil) {
        self.api = api
        _vm = State(wrappedValue: LeadsThreeColumnViewModel(api: api, cachedRepo: cachedRepo))
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            // Column 1 — Pipeline sidebar
            LeadPipelineSidebar(vm: vm.sidebar)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
        } content: {
            // Column 2 — Lead list
            leadListColumn
                .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 480)
        } detail: {
            // Column 3 — Lead detail
            detailColumn
        }
        .navigationSplitViewStyle(.balanced)
        .task { await vm.load() }
        .sheet(isPresented: $showingCreate, onDismiss: { Task { await vm.load() } }) {
            LeadCreateView(api: api)
        }
        .leadKeyboardShortcuts { action in
            handleShortcut(action)
        }
    }

    // MARK: - Column 2: Lead list

    private var leadListColumn: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            leadListContent
        }
        .navigationTitle(columnTitle)
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .searchable(text: $searchText, prompt: "Search leads")
        .onChange(of: searchText) { _, new in vm.onSearchChange(new) }
        .refreshable { await vm.forceRefresh() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingCreate = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("New lead")
                    .accessibilityIdentifier("leads.new")
            }
            ToolbarItem(placement: .automatic) {
                StalenessIndicator(lastSyncedAt: vm.lastSyncedAt)
            }
        }
    }

    @ViewBuilder
    private var leadListContent: some View {
        if vm.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage {
            errorView(err)
        } else if vm.filteredLeads.isEmpty {
            emptyView
        } else {
            List(vm.filteredLeads, selection: $vm.selectedLeadId) { lead in
                NavigationLink(value: lead.id) {
                    LeadListRow(lead: lead)
                }
                .listRowBackground(Color.bizarreSurface1)
                .leadContextMenu(lead: lead) { action in
                    Task { await vm.handleContextAction(action, for: lead) }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private var columnTitle: String {
        if let status = vm.sidebar.selectedStatus {
            return status.displayName
        }
        return "All Leads"
    }

    // MARK: - Column 3: Detail

    @ViewBuilder
    private var detailColumn: some View {
        if let id = vm.selectedLeadId {
            LeadDetailView(api: api, id: id)
        } else {
            detailPlaceholder
        }
    }

    private var detailPlaceholder: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "person.text.rectangle")
                    .font(.system(size: 52))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                Text("Select a lead")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Text("Choose from the list to view details.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Error / empty

    private func errorView(_ message: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Couldn't load leads")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text(message)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
            Button("Try again") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var emptyView: some View {
        if searchText.isEmpty && vm.sidebar.selectedStatus == nil {
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "sparkles")
                    .font(.system(size: 48))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                Text("No leads yet")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Button("Add Lead") { showingCreate = true }
                    .buttonStyle(.brandGlass)
                    .tint(.bizarreOrange)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 36))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                Text("No results")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Keyboard shortcut handler

    private func handleShortcut(_ action: LeadKeyboardShortcutAction) {
        switch action {
        case .newLead:
            showingCreate = true
        case .search:
            // Programmatic search focus is handled by the searchable modifier;
            // here we simply trigger a reload so the search field becomes visible.
            break
        case .refresh:
            Task { await vm.forceRefresh() }
        case .convertSelected:
            guard let id = vm.selectedLeadId,
                  let lead = vm.filteredLeads.first(where: { $0.id == id }) else { return }
            Task { await vm.handleContextAction(.convertToCustomer, for: lead) }
        case .archiveSelected:
            guard let id = vm.selectedLeadId,
                  let lead = vm.filteredLeads.first(where: { $0.id == id }) else { return }
            Task { await vm.handleContextAction(.archive, for: lead) }
        case .assignSelected:
            guard let id = vm.selectedLeadId,
                  let lead = vm.filteredLeads.first(where: { $0.id == id }) else { return }
            Task { await vm.handleContextAction(.assign, for: lead) }
        case .changeStatusSelected:
            // Opens status note sheet — handled by LeadDetailView; just focus the detail.
            break
        case .nextLead:
            vm.selectNext()
        case .previousLead:
            vm.selectPrevious()
        }
    }
}

// MARK: - LeadListRow (internal to this file — column 2 row)

private struct LeadListRow: View {
    let lead: Lead

    var body: some View {
        HStack(alignment: .top, spacing: BrandSpacing.md) {
            // Status accent dot
            Circle()
                .fill(LeadPipelineSidebarStatus.from(status: lead.status).accentColor)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(lead.displayName)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
                if let phone = lead.phone, !phone.isEmpty {
                    Text(PhoneFormatter.format(phone))
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .lineLimit(1)
                        .textSelection(.enabled)
                } else if let email = lead.email, !email.isEmpty {
                    Text(email)
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
            }

            Spacer(minLength: BrandSpacing.sm)

            VStack(alignment: .trailing, spacing: BrandSpacing.xxs) {
                if let status = lead.status, !status.isEmpty {
                    Text(status.capitalized)
                        .font(.brandLabelSmall())
                        .padding(.horizontal, BrandSpacing.sm)
                        .padding(.vertical, BrandSpacing.xxs)
                        .foregroundStyle(.bizarreOnSurface)
                        .background(Color.bizarreSurface2, in: Capsule())
                        .accessibilityLabel("Status \(status.capitalized)")
                }
                if let score = lead.leadScore {
                    Text("\(score)")
                        .font(.brandMono(size: 12))
                        .foregroundStyle(score >= 70 ? .bizarreSuccess : .bizarreOnSurfaceMuted)
                        .monospacedDigit()
                        .accessibilityLabel("Score \(score)")
                }
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("LeadsThreeColumnView") {
    LeadsThreeColumnView(api: PreviewAPIClient())
}

/// Stub client for preview only.
private actor PreviewAPIClient: APIClient {
    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func delete(_ path: String) async throws { throw APITransportError.noBaseURL }
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> { throw APITransportError.noBaseURL }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
    func authedDataRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        throw APITransportError.noBaseURL
    }
    func upload(
        _ data: Data,
        to path: String,
        fileName: String,
        mimeType: String,
        fields: [String: String]
    ) async throws -> Data {
        throw APITransportError.noBaseURL
    }
}
#endif
