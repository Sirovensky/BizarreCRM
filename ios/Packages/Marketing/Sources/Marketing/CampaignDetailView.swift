import SwiftUI
import Core
import DesignSystem
import Networking

@MainActor
@Observable
final class CampaignDetailViewModel {
    private(set) var campaign: Campaign?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var isSending = false
    private(set) var sendError: String?

    @ObservationIgnored private let api: APIClient
    let campaignId: String

    init(api: APIClient, campaignId: String) {
        self.api = api
        self.campaignId = campaignId
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            // Try loading from real server using numeric id; fall back to legacy path
            if let numericId = Int(campaignId) {
                let row = try await api.getCampaignServer(id: numericId)
                campaign = Campaign.from(row)
            } else {
                campaign = try await api.getCampaign(id: campaignId)
            }
        } catch {
            AppLog.ui.error("Campaign detail load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    func send() async {
        isSending = true
        sendError = nil
        defer { isSending = false }
        do {
            campaign = try await api.sendCampaign(id: campaignId)
        } catch {
            AppLog.ui.error("Campaign send failed: \(error.localizedDescription, privacy: .public)")
            sendError = error.localizedDescription
        }
    }
}

public struct CampaignDetailView: View {
    @State private var vm: CampaignDetailViewModel
    @State private var showApprovalSheet = false
    @State private var showAudiencePreview = false
    @State private var showAnalytics = false
    @State private var showCoupons = false
    @State private var managerPin = ""
    @State private var approvalError: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let api: APIClient

    public init(api: APIClient, campaignId: String) {
        self.api = api
        _vm = State(wrappedValue: CampaignDetailViewModel(api: api, campaignId: campaignId))
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            bodyContent
        }
        .navigationTitle(vm.campaign?.name ?? "Campaign")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        #endif
        .task { await vm.load() }
        .sheet(isPresented: $showApprovalSheet) { approvalSheet }
        .sheet(isPresented: $showAudiencePreview) {
            if let rowId = vm.campaign?.serverRowId {
                CampaignAudiencePreviewView(api: api, campaignId: rowId)
            }
        }
        .navigationDestination(isPresented: $showAnalytics) {
            if let rowId = vm.campaign?.serverRowId {
                CampaignAnalyticsView(api: api, campaignId: rowId)
            }
        }
        .navigationDestination(isPresented: $showCoupons) {
            CouponCodesView()
        }
        .toolbar { sendToolbar }
    }

    // MARK: - Body content

    @ViewBuilder
    private var bodyContent: some View {
        if vm.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage {
            errorPane(err)
        } else if let campaign = vm.campaign {
            detailContent(campaign)
        }
    }

    private func detailContent(_ campaign: Campaign) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                // Status + timestamps
                HStack {
                    CampaignStatusBadge(campaign.status)
                    Spacer()
                    Text(campaign.createdAt, style: .date)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }

                // Approval warning
                if let est = campaign.recipientsEstimate,
                   EstimatedCostCalculator.requiresApproval(recipients: est) {
                    approvalBanner(count: est)
                }

                // Audience
                section("Audience") {
                    infoRow("Segment ID", value: campaign.audienceSegmentId ?? "All contacts")
                    if let est = campaign.recipientsEstimate {
                        infoRow("Recipients", value: "\(est)")
                        infoRow("Estimated cost", value: EstimatedCostCalculator.formattedCost(recipients: est))
                    }
                }

                // Template
                section("Message (A)") {
                    Text(campaign.template)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .textSelection(.enabled)
                }

                if let b = campaign.variantB, !b.isEmpty {
                    section("Message (B)") {
                        Text(b)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurface)
                            .textSelection(.enabled)
                    }
                }

                // Schedule
                if let scheduled = campaign.scheduledAt {
                    section("Scheduled") {
                        Text(scheduled, style: .date)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurface)
                    }
                }

                // Action buttons (analytics, audience preview, coupons)
                actionButtonsSection(campaign)

                // Post-send report
                if campaign.status == .sent, let report = campaign.report {
                    reportSection(report)
                }

                // Send error
                if let err = vm.sendError {
                    Text(err)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreError)
                        .padding(BrandSpacing.md)
                        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.vertical, BrandSpacing.lg)
        }
    }

    // MARK: - Action buttons

    private func actionButtonsSection(_ campaign: Campaign) -> some View {
        VStack(spacing: BrandSpacing.sm) {
            if campaign.serverRowId != nil {
                HStack(spacing: BrandSpacing.sm) {
                    actionButton(
                        icon: "chart.bar.fill",
                        title: "Analytics",
                        a11yId: "marketing.campaign.analytics"
                    ) { showAnalytics = true }

                    actionButton(
                        icon: "person.3.fill",
                        title: "Audience",
                        a11yId: "marketing.campaign.audiencePreview"
                    ) { showAudiencePreview = true }
                }

                actionButton(
                    icon: "ticket.fill",
                    title: "Coupon Codes",
                    a11yId: "marketing.campaign.coupons"
                ) { showCoupons = true }
            }
        }
    }

    private func actionButton(
        icon: String,
        title: String,
        a11yId: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon).foregroundStyle(.bizarreOrange).accessibilityHidden(true)
                Text(title).font(.brandTitleSmall()).foregroundStyle(.bizarreOnSurface)
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.bizarreOnSurfaceMuted)
                    .font(.system(size: 12)).accessibilityHidden(true)
            }
            .padding(BrandSpacing.md)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 10))
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel(title)
        .accessibilityIdentifier(a11yId)
        #if canImport(UIKit)
        .hoverEffect(.highlight)
        #endif
    }

    // MARK: - Approval banner

    private func approvalBanner(count: Int) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.bizarreWarning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("Requires manager approval")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
                Text("Audience size \(count) exceeds 100-recipient limit")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .padding(BrandSpacing.md)
        .background(Color.bizarreWarning.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.bizarreWarning, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Warning: Requires manager approval. Audience of \(count) exceeds limit.")
    }

    // MARK: - Report

    private func reportSection(_ report: CampaignReport) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            Text("Post-send report")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: BrandSpacing.sm),
                    GridItem(.flexible(), spacing: BrandSpacing.sm)
                ],
                spacing: BrandSpacing.sm
            ) {
                StatTileCard(icon: "checkmark.circle.fill", label: "Delivered",
                             value: "\(report.delivered)", accent: .bizarreSuccess)
                StatTileCard(icon: "xmark.circle.fill", label: "Failed",
                             value: "\(report.failed)", accent: .bizarreError)
                StatTileCard(icon: "hand.raised.fill", label: "Opted-out",
                             value: "\(report.optedOut)", accent: .bizarreWarning)
                StatTileCard(icon: "bubble.left.fill", label: "Replies",
                             value: "\(report.replies)", accent: .bizarreTeal)
            }
        }
    }

    // MARK: - Helpers

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text(title)
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityAddTraits(.isHeader)
            content()
                .padding(BrandSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
            Spacer()
            Text(value).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurface).textSelection(.enabled)
        }
    }

    private func errorPane(_ msg: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36)).foregroundStyle(.bizarreError).accessibilityHidden(true)
            Text("Couldn't load campaign").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
            Text(msg).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted).multilineTextAlignment(.center)
            Button("Retry") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent).tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var sendToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            if let campaign = vm.campaign, campaign.status == .draft || campaign.status == .scheduled {
                let recipients = campaign.recipientsEstimate ?? 0
                let needsApproval = EstimatedCostCalculator.requiresApproval(recipients: recipients)

                if needsApproval {
                    Button("Request Approval") { showApprovalSheet = true }
                        .tint(.bizarreWarning)
                        .accessibilityIdentifier("marketing.campaign.requestApproval")
                } else {
                    Button("Send") {
                        Task { await vm.send() }
                    }
                    .disabled(vm.isSending)
                    .accessibilityIdentifier("marketing.campaign.send")
                }
            }
        }
    }

    // MARK: - Approval sheet

    private var approvalSheet: some View {
        NavigationStack {
            VStack(spacing: BrandSpacing.lg) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityHidden(true)
                Text("Manager PIN Required")
                    .font(.brandTitleLarge())
                    .foregroundStyle(.bizarreOnSurface)
                Text("This campaign requires manager approval before sending.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)

                SecureField("Manager PIN", text: $managerPin)
                    .textFieldStyle(.roundedBorder)
                    #if canImport(UIKit)
                    .keyboardType(.numberPad)
                    #endif
                    .accessibilityLabel("Manager PIN")

                if let err = approvalError {
                    Text(err)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreError)
                        .multilineTextAlignment(.center)
                }

                Button("Submit for Approval") {
                    Task {
                        let createVM = CampaignCreateViewModel(api: api)
                        let ok = await createVM.requestApprovalSend(
                            campaignId: vm.campaignId,
                            pin: managerPin
                        )
                        if ok {
                            showApprovalSheet = false
                            await vm.load()
                        } else {
                            approvalError = createVM.errorMessage ?? "Unknown error"
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
                .disabled(managerPin.isEmpty)
                .accessibilityIdentifier("marketing.campaign.submitApproval")
            }
            .padding(BrandSpacing.xl)
            .navigationTitle("Approval")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showApprovalSheet = false }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
