import SwiftUI
import Core
import DesignSystem
import Networking

public struct CampaignListView: View {
    @State private var vm: CampaignListViewModel
    @State private var showingCreate = false
    @State private var selectedCampaignId: String? = nil
    @State private var selectedCampaignRowId: Int? = nil
    @State private var confirmDelete: Campaign? = nil
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
        _vm = State(wrappedValue: CampaignListViewModel(api: api))
    }

    public var body: some View {
        Group {
            if Platform.isCompact { compactLayout } else { regularLayout }
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .sheet(isPresented: $showingCreate, onDismiss: { Task { await vm.load() } }) {
            CampaignCreateView(api: api)
        }
        .confirmationDialog(
            "Delete \"\(confirmDelete?.name ?? "")\"?",
            isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let c = confirmDelete, let rowId = c.serverRowId {
                    Task { await vm.delete(id: rowId) }
                }
                confirmDelete = nil
            }
            Button("Cancel", role: .cancel) { confirmDelete = nil }
        }
    }

    // MARK: - Filter tabs

    private var filterPicker: some View {
        Picker("Filter", selection: $vm.filter) {
            ForEach(CampaignListFilter.allCases, id: \.self) { f in
                Text(f.displayName).tag(f)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityLabel("Campaign filter")
    }

    // MARK: - Layouts

    private var compactLayout: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: 0) {
                    filterPicker
                    content
                }
            }
            .navigationTitle("Campaigns")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            #endif
            .toolbar { newButton }
            .navigationDestination(for: String.self) { id in
                CampaignDetailView(api: api, campaignId: id)
            }
        }
    }

    private var regularLayout: some View {
        NavigationSplitView {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: 0) {
                    filterPicker
                    content
                }
            }
            .navigationTitle("Campaigns")
            .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 480)
            #if canImport(UIKit)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            #endif
            .toolbar { newButton }
        } content: {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                if let id = selectedCampaignId {
                    CampaignDetailView(api: api, campaignId: id)
                } else {
                    emptyDetail(icon: "megaphone.fill", message: "Select a campaign")
                }
            }
        } detail: {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                if let rowId = selectedCampaignRowId {
                    CampaignAnalyticsView(api: api, campaignId: rowId)
                } else {
                    emptyDetail(icon: "chart.bar.fill", message: "Select a campaign to view analytics")
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    private func emptyDetail(icon: String, message: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 52))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text(message)
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.campaigns.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage, vm.campaigns.isEmpty {
            errorView(err)
        } else if vm.campaigns.isEmpty {
            emptyDetail(icon: "megaphone", message: "No campaigns yet")
        } else {
            campaignList
        }
    }

    @ViewBuilder
    private func campaignRow(for campaign: Campaign) -> some View {
        if Platform.isCompact {
            NavigationLink(value: campaign.id) {
                CampaignRow(campaign: campaign)
            }
            .listRowBackground(Color.bizarreSurface1)
            #if canImport(UIKit)
            .hoverEffect(.highlight)
            #endif
            .contextMenu { rowContextMenu(campaign) }
        } else {
            Button {
                selectedCampaignId = campaign.id
                selectedCampaignRowId = campaign.serverRowId
            } label: {
                HStack {
                    CampaignRow(campaign: campaign)
                    if selectedCampaignId == campaign.id {
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.bizarreOrange)
                            .accessibilityHidden(true)
                    }
                }
            }
            .listRowBackground(
                selectedCampaignId == campaign.id
                    ? Color.bizarreOrange.opacity(0.12)
                    : Color.bizarreSurface1
            )
            #if canImport(UIKit)
            .hoverEffect(.highlight)
            #endif
            .contextMenu { rowContextMenu(campaign) }
        }
    }

    @ViewBuilder
    private func rowContextMenu(_ campaign: Campaign) -> some View {
        if let rowId = campaign.serverRowId {
            Button(role: .destructive) {
                confirmDelete = campaign
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .accessibilityLabel("Delete \(campaign.name)")
            Button {
                Task {
                    let body = PatchCampaignServerRequest(
                        status: campaign.status == .active ? "paused" : "active"
                    )
                    _ = try? await api.patchCampaignServer(id: rowId, body)
                    await vm.load()
                }
            } label: {
                Label(
                    campaign.status == .active ? "Pause" : "Activate",
                    systemImage: campaign.status == .active ? "pause.circle" : "play.circle"
                )
            }
        }
    }

    private var campaignList: some View {
        List {
            ForEach(vm.campaigns) { campaign in
                campaignRow(for: campaign)
            }
            if vm.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }
        }
        #if canImport(UIKit)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .scrollContentBackground(.hidden)
        .animation(.easeInOut(duration: 0.2), value: vm.filter)
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36)).foregroundStyle(.bizarreError).accessibilityHidden(true)
            Text("Couldn't load campaigns").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
            Text(msg).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted).multilineTextAlignment(.center)
            Button("Try again") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent).tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Toolbar

    private var newButton: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { showingCreate = true } label: { Image(systemName: "plus") }
                .accessibilityLabel("New campaign")
                .accessibilityIdentifier("marketing.campaigns.new")
                #if canImport(UIKit)
                .keyboardShortcut("N", modifiers: .command)
                #endif
        }
    }
}

// MARK: - Row

private struct CampaignRow: View {
    let campaign: Campaign

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        HStack(alignment: .center, spacing: BrandSpacing.md) {
            Image(systemName: campaign.type.systemImage)
                .font(.system(size: 18))
                .foregroundStyle(.bizarreOrange)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(campaign.name)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
                HStack(spacing: BrandSpacing.xs) {
                    Image(systemName: campaign.channel.systemImage)
                        .font(.system(size: 10))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityHidden(true)
                    Text(campaign.channel.displayName)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    Text("·")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    Text(Self.relativeFormatter.localizedString(for: campaign.createdAt, relativeTo: Date()))
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
            Spacer(minLength: 0)
            CampaignStatusBadge(campaign.status)
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(campaign.name), \(campaign.channel.displayName), \(campaign.status.displayName), created \(Self.relativeFormatter.localizedString(for: campaign.createdAt, relativeTo: Date()))")
    }
}
