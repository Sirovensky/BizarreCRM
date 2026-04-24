import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - MarketingThreeColumnView

/// iPad 3-column layout for the Marketing module.
///
/// Column 1 (sidebar):  `MarketingKindSidebar` — Campaigns / Coupons / Referrals / Reviews
/// Column 2 (content):  Kind-specific list (Campaigns list, Coupons grid, etc.)
/// Column 3 (detail):   `CampaignAnalyticsInspector` when a campaign is selected;
///                       detail content for other kinds.
///
/// Liquid Glass chrome applied to navigation bars via `.toolbarBackground(.ultraThinMaterial)`.
/// Gate on `!Platform.isCompact` at the call site — this view is iPad-only.
public struct MarketingThreeColumnView: View {
    @State private var selectedKind: MarketingKind? = .campaigns
    @State private var selectedCampaign: Campaign? = nil
    @State private var showingCreateCampaign = false
    @State private var listVM: CampaignListViewModel
    @State private var contextMenuVM: CampaignContextMenuViewModel
    @State private var previewCampaign: Campaign? = nil

    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
        _listVM = State(wrappedValue: CampaignListViewModel(api: api))
        _contextMenuVM = State(wrappedValue: CampaignContextMenuViewModel(api: api))
    }

    public var body: some View {
        NavigationSplitView {
            MarketingKindSidebar(selection: $selectedKind)
        } content: {
            contentColumn
        } detail: {
            detailColumn
        }
        .navigationSplitViewStyle(.balanced)
        .marketingKeyboardShortcuts(
            onNewCampaign: { showingCreateCampaign = true },
            onRefresh:     { Task { await listVM.load() } },
            onRunNow:      {
                guard let c = selectedCampaign, let id = c.serverRowId else { return }
                Task { _ = try? await api.runCampaignNow(id: id) }
            },
            onDuplicate:   {
                guard let c = selectedCampaign else { return }
                Task { await contextMenuVM.duplicate(campaign: c) }
            },
            onKindChange:  { kind in selectedKind = kind }
        )
        .sheet(isPresented: $showingCreateCampaign, onDismiss: { Task { await listVM.load() } }) {
            CampaignCreateView(api: api)
        }
        .sheet(item: $previewCampaign) { campaign in
            if let rowId = campaign.serverRowId {
                CampaignAudiencePreviewView(api: api, campaignId: rowId)
            }
        }
    }

    // MARK: - Content column (column 2)

    @ViewBuilder
    private var contentColumn: some View {
        switch selectedKind ?? .campaigns {
        case .campaigns:
            campaignsContent
        case .coupons:
            NavigationStack {
                CouponCodesView()
            }
        case .referrals:
            NavigationStack {
                ReferralLeaderboardView(service: ReferralService(api: api))
            }
        case .reviews:
            NavigationStack {
                ReviewSettingsView(api: api)
            }
        }
    }

    private var campaignsContent: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            VStack(spacing: 0) {
                filterPicker
                campaignListContent
            }
        }
        .navigationTitle("Campaigns")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingCreateCampaign = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New campaign")
                .accessibilityIdentifier("marketing.campaigns.new")
                #if canImport(UIKit)
                .keyboardShortcut("N", modifiers: .command)
                #endif
            }
        }
        .task { await listVM.load() }
        .refreshable { await listVM.load() }
    }

    private var filterPicker: some View {
        Picker("Filter", selection: $listVM.filter) {
            ForEach(CampaignListFilter.allCases, id: \.self) { f in
                Text(f.displayName).tag(f)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityLabel("Campaign filter")
    }

    @ViewBuilder
    private var campaignListContent: some View {
        if listVM.isLoading && listVM.campaigns.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = listVM.errorMessage, listVM.campaigns.isEmpty {
            campaignErrorView(err)
        } else if listVM.campaigns.isEmpty {
            emptyCampaigns
        } else {
            campaignList
        }
    }

    private var emptyCampaigns: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "megaphone")
                .font(.system(size: 48))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("No campaigns yet")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var campaignList: some View {
        List(listVM.campaigns, selection: $selectedCampaign) { campaign in
            campaignRow(for: campaign)
        }
        #if canImport(UIKit)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .scrollContentBackground(.hidden)
        .animation(.easeInOut(duration: DesignTokens.Motion.quick), value: listVM.filter)
    }

    private func campaignRow(for campaign: Campaign) -> some View {
        Button {
            selectedCampaign = campaign
        } label: {
            HStack {
                campaignRowContent(campaign)
                if selectedCampaign?.id == campaign.id {
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.bizarreOrange)
                        .accessibilityHidden(true)
                }
            }
        }
        .listRowBackground(
            selectedCampaign?.id == campaign.id
                ? Color.bizarreOrange.opacity(0.12)
                : Color.bizarreSurface1
        )
        #if canImport(UIKit)
        .hoverEffect(.highlight)
        #endif
        .campaignContextMenu(campaign, actions: contextActions)
    }

    private func campaignRowContent(_ campaign: Campaign) -> some View {
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
                }
            }
            Spacer(minLength: 0)
            CampaignStatusBadge(campaign.status)
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(campaign.name), \(campaign.channel.displayName), \(campaign.status.displayName)")
    }

    private var contextActions: CampaignContextMenuActions {
        CampaignContextMenuActions(
            // Edit: navigate to detail view (detail column shows CampaignDetailView)
            onEdit: { c in selectedCampaign = c },
            onSendNow: { [api] c in
                guard let id = c.serverRowId else { return }
                _ = try? await api.runCampaignNow(id: id)
                await listVM.load()
            },
            onPreview: { c in previewCampaign = c },
            onDuplicate: { c in
                await contextMenuVM.duplicate(campaign: c)
                await listVM.load()
            },
            onArchive: { c in
                await contextMenuVM.archive(campaign: c)
                await listVM.load()
            }
        )
    }

    private func campaignErrorView(_ msg: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Couldn't load campaigns")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text(msg)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
            Button("Try again") { Task { await listVM.load() } }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Detail column (column 3)

    @ViewBuilder
    private var detailColumn: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            if let campaign = selectedCampaign, let rowId = campaign.serverRowId {
                VStack(spacing: 0) {
                    CampaignDetailView(api: api, campaignId: campaign.id)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .safeAreaInset(edge: .trailing, spacing: 0) {
                    CampaignAnalyticsInspector(api: api, campaignId: rowId)
                        .frame(width: 280)
                        .padding(.vertical, BrandSpacing.base)
                        .padding(.trailing, BrandSpacing.base)
                }
            } else {
                detailPlaceholder
            }
        }
        .navigationTitle(selectedCampaign?.name ?? "")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        #endif
    }

    private var detailPlaceholder: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 52))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("Select a campaign to view details")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("Choose from the list on the left")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No campaign selected. Choose from the list.")
    }
}
