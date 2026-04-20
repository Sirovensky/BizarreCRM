import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

@MainActor
@Observable
public final class LeadListViewModel {
    public private(set) var items: [Lead] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public var searchQuery: String = ""

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    public init(api: APIClient) { self.api = api }

    public func load() async {
        if items.isEmpty { isLoading = true }
        defer { isLoading = false }
        errorMessage = nil
        do { items = try await api.listLeads(keyword: searchQuery.isEmpty ? nil : searchQuery) }
        catch {
            AppLog.ui.error("Leads load failed: \(error.localizedDescription, privacy: .public)")
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
}

public struct LeadListView: View {
    @State private var vm: LeadListViewModel
    @State private var searchText: String = ""
    @State private var showingCreate: Bool = false
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
        _vm = State(wrappedValue: LeadListViewModel(api: api))
    }

    public var body: some View {
        Group {
            if Platform.isCompact {
                compactLayout
            } else {
                regularLayout
            }
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .sheet(isPresented: $showingCreate, onDismiss: { Task { await vm.load() } }) {
            LeadCreateView(api: api)
        }
    }

    private var compactLayout: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle("Leads")
            .searchable(text: $searchText, prompt: "Search leads")
            .onChange(of: searchText) { _, new in vm.onSearchChange(new) }
            .toolbar { newButton }
        }
    }

    private var regularLayout: some View {
        NavigationSplitView {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle("Leads")
            .searchable(text: $searchText, prompt: "Search leads")
            .onChange(of: searchText) { _, new in vm.onSearchChange(new) }
            .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 520)
            .toolbar { newButton }
        } detail: {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: BrandSpacing.md) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 52))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityHidden(true)
                    Text("Select a lead")
                        .font(.brandTitleMedium())
                        .foregroundStyle(.bizarreOnSurface)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("")
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var newButton: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { showingCreate = true } label: { Image(systemName: "plus") }
                .keyboardShortcut("N", modifiers: .command)
                .accessibilityLabel("New lead")
                .accessibilityIdentifier("leads.new")
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage {
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 36)).foregroundStyle(.bizarreError)
                    .accessibilityHidden(true)
                Text("Couldn't load leads").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
                Text(err).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted).multilineTextAlignment(.center)
                Button("Try again") { Task { await vm.load() } }.buttonStyle(.borderedProminent).tint(.bizarreOrange)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.items.isEmpty {
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "sparkles").font(.system(size: 48)).foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                Text(searchText.isEmpty ? "No leads yet" : "No results")
                    .font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(vm.items) { lead in
                    Row(lead: lead)
                        .listRowBackground(Color.bizarreSurface1)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private struct Row: View {
        let lead: Lead

        var body: some View {
            HStack(alignment: .top, spacing: BrandSpacing.md) {
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(lead.displayName)
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                        .lineLimit(1)
                    if let order = lead.orderId, !order.isEmpty {
                        Text(order).font(.brandMono(size: 12)).foregroundStyle(.bizarreOnSurfaceMuted)
                            .textSelection(.enabled)
                    }
                    if let phone = lead.phone, !phone.isEmpty {
                        Text(PhoneFormatter.format(phone)).font(.brandLabelLarge()).foregroundStyle(.bizarreOnSurfaceMuted).lineLimit(1)
                            .textSelection(.enabled)
                    } else if let email = lead.email, !email.isEmpty {
                        Text(email).font(.brandLabelLarge()).foregroundStyle(.bizarreOnSurfaceMuted).lineLimit(1)
                            .textSelection(.enabled)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: BrandSpacing.xxs) {
                    if let status = lead.status {
                        let statusLabel = status.capitalized
                        Text(statusLabel)
                            .font(.brandLabelSmall())
                            .padding(.horizontal, BrandSpacing.sm).padding(.vertical, BrandSpacing.xxs)
                            .foregroundStyle(.bizarreOnSurface)
                            .background(Color.bizarreSurface2, in: Capsule())
                            .accessibilityLabel("Status \(statusLabel)")
                    }
                    if let score = lead.leadScore {
                        Text("\(score)/100")
                            .font(.brandMono(size: 12))
                            .foregroundStyle(score >= 70 ? .bizarreSuccess : .bizarreOnSurfaceMuted)
                            .monospacedDigit()
                    }
                }
            }
            .padding(.vertical, BrandSpacing.xs)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Self.a11y(for: lead))
        }

        static func a11y(for lead: Lead) -> String {
            var parts: [String] = [lead.displayName]
            if let order = lead.orderId, !order.isEmpty { parts.append(order) }
            if let phone = lead.phone, !phone.isEmpty {
                parts.append(PhoneFormatter.format(phone))
            } else if let email = lead.email, !email.isEmpty {
                parts.append(email)
            }
            if let status = lead.status, !status.isEmpty { parts.append("Status \(status.capitalized)") }
            if let score = lead.leadScore { parts.append("Score \(score) of 100") }
            return parts.joined(separator: ". ")
        }
    }
}
