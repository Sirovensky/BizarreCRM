import SwiftUI
import Core
import DesignSystem
import Networking

public struct CampaignListView: View {
    @State private var vm: CampaignListViewModel
    @State private var showingCreate = false
    @State private var selectedCampaignId: String? = nil
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
    }

    // MARK: - Layouts

    private var compactLayout: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle("Campaigns")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                newButton
            }
            .navigationDestination(for: String.self) { id in
                CampaignDetailView(api: api, campaignId: id)
            }
        }
    }

    private var regularLayout: some View {
        NavigationSplitView {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle("Campaigns")
            .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 480)
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
                emptyDetail(icon: "chart.bar.fill", message: "Campaign preview")
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

    private var campaignList: some View {
        List {
            ForEach(vm.campaigns) { campaign in
                NavigationLink(value: campaign.id) {
                    CampaignRow(campaign: campaign)
                }
                .listRowBackground(Color.bizarreSurface1)
                #if canImport(UIKit)
                .hoverEffect(.highlight)
                #endif
                .onAppear {
                    if campaign.id == vm.campaigns.last?.id && vm.hasMore {
                        Task { await vm.loadNextPage() }
                    }
                }
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
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(campaign.name)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
                Text(Self.relativeFormatter.localizedString(for: campaign.createdAt, relativeTo: Date()))
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer(minLength: 0)
            CampaignStatusBadge(campaign.status)
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(campaign.name), \(campaign.status.displayName), created \(Self.relativeFormatter.localizedString(for: campaign.createdAt, relativeTo: Date()))")
    }
}
