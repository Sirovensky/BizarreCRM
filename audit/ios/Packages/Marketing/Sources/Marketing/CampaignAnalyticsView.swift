import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - ViewModel

@MainActor
@Observable
public final class CampaignAnalyticsViewModel {
    public private(set) var stats: CampaignStats?
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public private(set) var isRunning = false
    public private(set) var runResult: CampaignRunNowResult?
    public private(set) var runError: String?

    @ObservationIgnored private let api: APIClient
    public let campaignId: Int

    public init(api: APIClient, campaignId: Int) {
        self.api = api
        self.campaignId = campaignId
    }

    public func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            stats = try await api.getCampaignStats(id: campaignId)
        } catch {
            AppLog.ui.error("Campaign stats load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    public func runNow() async {
        isRunning = true
        runError = nil
        runResult = nil
        defer { isRunning = false }
        do {
            runResult = try await api.runCampaignNow(id: campaignId)
            // Reload stats after running
            await load()
        } catch {
            AppLog.ui.error("Campaign run-now failed: \(error.localizedDescription, privacy: .public)")
            runError = error.localizedDescription
        }
    }
}

// MARK: - View

/// Read-only analytics for a campaign: sent/delivered/clicked/replied.
/// Also exposes "Run now" which dispatches the campaign.
public struct CampaignAnalyticsView: View {
    @State private var vm: CampaignAnalyticsViewModel
    @State private var showRunConfirm = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(api: APIClient, campaignId: Int) {
        _vm = State(wrappedValue: CampaignAnalyticsViewModel(api: api, campaignId: campaignId))
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            bodyContent
        }
        .navigationTitle("Analytics")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        #endif
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .toolbar { refreshButton }
        .confirmationDialog(
            "Send this campaign to all eligible recipients now?",
            isPresented: $showRunConfirm,
            titleVisibility: .visible
        ) {
            Button("Run now", role: .destructive) { Task { await vm.runNow() } }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Body

    @ViewBuilder
    private var bodyContent: some View {
        if vm.isLoading && vm.stats == nil {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage, vm.stats == nil {
            errorPane(err)
        } else if let stats = vm.stats {
            analyticsContent(stats)
        }
    }

    private func analyticsContent(_ stats: CampaignStats) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {

                // Campaign info header
                campaignHeader(stats.campaign)

                // Unsubscribe alarm — shown prominently if rate >= 2%
                if let rate = stats.counts.unsubscribeRate, rate >= 0.02 {
                    unsubscribeAlarmBanner(rate: rate, optedOut: stats.counts.optedOut ?? 0)
                }

                // Stat grid — iPhone 2-col, iPad 4-col
                statsGrid(stats.counts, campaign: stats.campaign)

                // Revenue tile (if available)
                if let revCents = stats.counts.convertedRevenueCents {
                    revenueTile(cents: revCents)
                }

                // Unsubscribe rate row (always visible when data present)
                if let optedOut = stats.counts.optedOut {
                    unsubscribeRateRow(optedOut: optedOut, sent: stats.counts.sent)
                }

                // Run now / send confirmation
                if stats.campaign.status != "archived" {
                    runNowSection
                }

                // Run result banner
                if let result = vm.runResult {
                    runResultBanner(result)
                }

                if let err = vm.runError {
                    Text(err)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreError)
                        .padding(BrandSpacing.md)
                        .background(Color.bizarreError.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.vertical, BrandSpacing.lg)
        }
    }

    private func campaignHeader(_ campaign: CampaignServerRow) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text(campaign.name)
                .font(.brandTitleLarge())
                .foregroundStyle(.bizarreOnSurface)
                .textSelection(.enabled)
            HStack(spacing: BrandSpacing.sm) {
                Text(campaign.type.capitalized.replacingOccurrences(of: "_", with: " "))
                    .font(.brandLabelSmall())
                    .padding(.horizontal, BrandSpacing.sm)
                    .padding(.vertical, 2)
                    .foregroundStyle(.bizarreOnSurface)
                    .background(Color.bizarreSurface2, in: Capsule())
                Text(campaign.channel.uppercased())
                    .font(.brandLabelSmall())
                    .padding(.horizontal, BrandSpacing.sm)
                    .padding(.vertical, 2)
                    .foregroundStyle(.bizarreOrange)
                    .background(Color.bizarreOrange.opacity(0.15), in: Capsule())
                if let last = campaign.lastRunAt {
                    Text("Last run: \(last)")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(campaign.name), type: \(campaign.type), channel: \(campaign.channel)")
    }

    private func statsGrid(_ counts: CampaignStatCounts, campaign: CampaignServerRow) -> some View {
        let columns: [GridItem] = Platform.isCompact
            ? [GridItem(.flexible()), GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible()),
               GridItem(.flexible()), GridItem(.flexible())]

        return LazyVGrid(columns: columns, spacing: BrandSpacing.sm) {
            StatTileCard(icon: "paperplane.fill",       label: "Sent",      value: "\(campaign.sentCount)",    accent: .bizarreOrange)
            StatTileCard(icon: "checkmark.circle.fill", label: "Delivered", value: "\(counts.sent)",           accent: .bizarreSuccess)
            StatTileCard(icon: "bubble.left.fill",      label: "Replied",   value: "\(campaign.repliedCount)", accent: .bizarreTeal)
            StatTileCard(icon: "arrow.right.circle.fill", label: "Converted", value: "\(campaign.convertedCount)", accent: .bizarreMagenta)
        }
        .accessibilityElement(children: .contain)
    }

    private func unsubscribeAlarmBanner(rate: Double, optedOut: Int) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.white)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("High unsubscribe rate: \(Int(rate * 100))%")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.white)
                Text("\(optedOut) recipient(s) opted out — review message relevance and audience targeting.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreError, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Warning: High unsubscribe rate of \(Int(rate * 100)) percent. \(optedOut) recipients opted out.")
    }

    private func revenueTile(cents: Int) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "dollarsign.circle.fill")
                .foregroundStyle(.bizarreSuccess)
                .font(.system(size: 28))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Attributed Revenue")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Text(String(format: "$%.2f", Double(cents) / 100))
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding(BrandSpacing.md)
        .background(Color.bizarreSuccess.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Attributed revenue: \(String(format: "$%.2f", Double(cents) / 100))")
    }

    private func unsubscribeRateRow(optedOut: Int, sent: Int) -> some View {
        let rate = sent > 0 ? Double(optedOut) / Double(sent) : 0
        let isHigh = rate >= 0.02
        // Color semantic: high = error red; non-zero = warning amber; zero = muted.
        let chipColor: Color = isHigh ? .bizarreError : (optedOut > 0 ? .bizarreWarning : .bizarreOnSurfaceMuted)
        return HStack(spacing: BrandSpacing.sm) {
            Image(systemName: isHigh ? "exclamationmark.triangle.fill" : "hand.raised.slash.fill")
                .foregroundStyle(chipColor)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text("Unsubscribes: \(optedOut)")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
            Spacer(minLength: 0)
            // Opt-out chip: coloured pill so it stands out from plain metric tiles.
            Text(String(format: "%.1f%%", rate * 100))
                .font(.brandTitleSmall())
                .monospacedDigit()
                .padding(.horizontal, BrandSpacing.sm)
                .padding(.vertical, 2)
                .foregroundStyle(chipColor)
                .background(chipColor.opacity(0.12), in: Capsule())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Unsubscribe rate: \(String(format: "%.1f", rate * 100)) percent")
    }

    private var runNowSection: some View {
        Button {
            showRunConfirm = true
        } label: {
            HStack {
                if vm.isRunning {
                    ProgressView()
                        .scaleEffect(0.8)
                        .padding(.trailing, BrandSpacing.xs)
                } else {
                    Image(systemName: "bolt.fill")
                        .accessibilityHidden(true)
                }
                Text(vm.isRunning ? "Sending…" : "Run now")
                    .font(.brandTitleSmall())
            }
            .frame(maxWidth: .infinity)
            .padding(BrandSpacing.md)
            .foregroundStyle(.white)
            .background(
                vm.isRunning ? Color.bizarreOrange.opacity(0.6) : Color.bizarreOrange,
                in: RoundedRectangle(cornerRadius: 12)
            )
        }
        .disabled(vm.isRunning)
        .accessibilityLabel(vm.isRunning ? "Sending campaign" : "Run campaign now")
        .accessibilityIdentifier("marketing.campaign.runNow")
    }

    private func runResultBanner(_ result: CampaignRunNowResult) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.bizarreSuccess)
                    .accessibilityHidden(true)
                Text("Campaign dispatched")
                    .font(.brandTitleSmall()).foregroundStyle(.bizarreOnSurface)
            }
            HStack(spacing: BrandSpacing.lg) {
                stat("Attempted", value: "\(result.attempted)")
                stat("Sent",      value: "\(result.sent)")
                stat("Failed",    value: "\(result.failed)")
                stat("Skipped",   value: "\(result.skipped)")
            }
        }
        .padding(BrandSpacing.md)
        .background(Color.bizarreSuccess.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.bizarreSuccess, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Campaign dispatched. Attempted \(result.attempted), sent \(result.sent), failed \(result.failed).")
    }

    private func stat(_ label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface).monospacedDigit()
            Text(label).font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    private func errorPane(_ msg: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36)).foregroundStyle(.bizarreError).accessibilityHidden(true)
            Text("Couldn't load analytics").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
            Text(msg).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent).tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var refreshButton: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { Task { await vm.load() } } label: {
                Image(systemName: "arrow.clockwise")
            }
            .accessibilityLabel("Refresh analytics")
            .disabled(vm.isLoading)
        }
    }
}

