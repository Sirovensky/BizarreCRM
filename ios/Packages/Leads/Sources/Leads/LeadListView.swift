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
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            content
        }
        .navigationTitle("Leads")
        .searchable(text: $searchText, prompt: "Search leads")
        .onChange(of: searchText) { _, new in vm.onSearchChange(new) }
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingCreate = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showingCreate, onDismiss: { Task { await vm.load() } }) {
            LeadCreateView(api: api)
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage {
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 36)).foregroundStyle(.bizarreError)
                Text("Couldn't load leads").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
                Text(err).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted).multilineTextAlignment(.center)
                Button("Try again") { Task { await vm.load() } }.buttonStyle(.borderedProminent).tint(.bizarreOrange)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.items.isEmpty {
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "sparkles").font(.system(size: 48)).foregroundStyle(.bizarreOnSurfaceMuted)
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
                    }
                    if let phone = lead.phone, !phone.isEmpty {
                        Text(PhoneFormatter.format(phone)).font(.brandLabelLarge()).foregroundStyle(.bizarreOnSurfaceMuted).lineLimit(1)
                    } else if let email = lead.email, !email.isEmpty {
                        Text(email).font(.brandLabelLarge()).foregroundStyle(.bizarreOnSurfaceMuted).lineLimit(1)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: BrandSpacing.xxs) {
                    if let status = lead.status {
                        Text(status.capitalized)
                            .font(.brandLabelSmall())
                            .padding(.horizontal, BrandSpacing.sm).padding(.vertical, BrandSpacing.xxs)
                            .foregroundStyle(.bizarreOnSurface)
                            .background(Color.bizarreSurface2, in: Capsule())
                    }
                    if let score = lead.leadScore {
                        Text("\(score)/100")
                            .font(.brandMono(size: 12))
                            .foregroundStyle(score >= 70 ? .bizarreSuccess : .bizarreOnSurfaceMuted)
                    }
                }
            }
            .padding(.vertical, BrandSpacing.xs)
        }
    }
}
