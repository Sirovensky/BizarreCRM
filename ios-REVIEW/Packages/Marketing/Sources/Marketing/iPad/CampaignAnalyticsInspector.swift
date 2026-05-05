import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - CampaignAnalyticsInspector

/// Inline send-stats panel for the 3-column iPad detail column.
/// Loads stats via GET /campaigns/:id/stats and exposes a "Run Now" button
/// (POST /campaigns/:id/run-now) with confirmation.
///
/// Designed as a side-panel companion to `CampaignDetailView` — does NOT push
/// navigation; it overlays the detail column in place.
public struct CampaignAnalyticsInspector: View {
    @State private var vm: CampaignAnalyticsViewModel
    @State private var showRunConfirm = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(api: APIClient, campaignId: Int) {
        _vm = State(wrappedValue: CampaignAnalyticsViewModel(api: api, campaignId: campaignId))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            inspectorHeader
            Divider().padding(.horizontal, BrandSpacing.base)
            Group {
                if vm.isLoading && vm.stats == nil {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 120)
                        .padding(BrandSpacing.base)
                } else if let err = vm.errorMessage, vm.stats == nil {
                    errorPane(err)
                } else if let stats = vm.stats {
                    inspectorBody(stats)
                } else {
                    emptyPane
                }
            }
        }
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .task { await vm.load() }
        .confirmationDialog(
            "Send this campaign to all eligible recipients now?",
            isPresented: $showRunConfirm,
            titleVisibility: .visible
        ) {
            Button("Run Now", role: .destructive) { Task { await vm.runNow() } }
            Button("Cancel", role: .cancel) {}
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Campaign analytics inspector")
    }

    // MARK: - Header

    private var inspectorHeader: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "chart.bar.fill")
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
            Text("Analytics")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Spacer()
            Button {
                Task { await vm.load() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .medium))
            }
            .disabled(vm.isLoading)
            .accessibilityLabel("Refresh analytics")
            .accessibilityIdentifier("marketing.inspector.refresh")
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.md)
    }

    // MARK: - Body

    private func inspectorBody(_ stats: CampaignStats) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.md) {
                statsGrid(stats)
                runNowSection(stats)
                if let result = vm.runResult {
                    runResultBanner(result)
                }
                if let err = vm.runError {
                    Text(err)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreError)
                        .padding(BrandSpacing.md)
                        .background(Color.bizarreError.opacity(0.1),
                                    in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                }
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.vertical, BrandSpacing.md)
        }
    }

    // MARK: - Stats Grid  (2-column on the inspector panel — narrower than full analytics)

    private func statsGrid(_ stats: CampaignStats) -> some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: BrandSpacing.sm),
                      GridItem(.flexible(), spacing: BrandSpacing.sm)],
            spacing: BrandSpacing.sm
        ) {
            StatTileCard(
                icon: "paperplane.fill",
                label: "Sent",
                value: "\(stats.campaign.sentCount)",
                accent: .bizarreOrange
            )
            StatTileCard(
                icon: "checkmark.circle.fill",
                label: "Delivered",
                value: "\(stats.counts.sent)",
                accent: .bizarreSuccess
            )
            StatTileCard(
                icon: "bubble.left.fill",
                label: "Replied",
                value: "\(stats.campaign.repliedCount)",
                accent: .bizarreTeal
            )
            StatTileCard(
                icon: "arrow.right.circle.fill",
                label: "Converted",
                value: "\(stats.campaign.convertedCount)",
                accent: .bizarreMagenta
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Send statistics")
    }

    // MARK: - Run now

    private func runNowSection(_ stats: CampaignStats) -> some View {
        Button {
            showRunConfirm = true
        } label: {
            HStack {
                if vm.isRunning {
                    ProgressView().scaleEffect(0.8).padding(.trailing, BrandSpacing.xs)
                } else {
                    Image(systemName: "bolt.fill").accessibilityHidden(true)
                }
                Text(vm.isRunning ? "Sending…" : "Run Now")
                    .font(.brandTitleSmall())
            }
            .frame(maxWidth: .infinity)
            .padding(BrandSpacing.md)
        }
        .buttonStyle(.brandGlassProminent)
        .tint(.bizarreOrange)
        .disabled(vm.isRunning || stats.campaign.status == "archived")
        .accessibilityLabel(vm.isRunning ? "Sending campaign" : "Run campaign now")
        .accessibilityIdentifier("marketing.inspector.runNow")
    }

    // MARK: - Run result banner

    private func runResultBanner(_ result: CampaignRunNowResult) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.bizarreSuccess)
                    .accessibilityHidden(true)
                Text("Campaign dispatched")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
            }
            HStack(spacing: BrandSpacing.lg) {
                miniStat("Attempted", "\(result.attempted)")
                miniStat("Sent",      "\(result.sent)")
                miniStat("Failed",    "\(result.failed)")
                miniStat("Skipped",   "\(result.skipped)")
            }
        }
        .padding(BrandSpacing.md)
        .background(Color.bizarreSuccess.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
            .strokeBorder(.bizarreSuccess, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Campaign dispatched. Attempted \(result.attempted), sent \(result.sent), failed \(result.failed).")
    }

    private func miniStat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreOnSurface)
                .monospacedDigit()
            Text(label)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    // MARK: - Empty / Error

    private var emptyPane: some View {
        VStack(spacing: BrandSpacing.sm) {
            Image(systemName: "chart.bar")
                .font(.system(size: 32))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("No stats yet")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
        .padding(BrandSpacing.base)
    }

    private func errorPane(_ msg: String) -> some View {
        VStack(spacing: BrandSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Couldn't load stats")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
            Button("Retry") { Task { await vm.load() } }
                .buttonStyle(.brandGlass)
                .tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
        .padding(BrandSpacing.base)
    }
}
