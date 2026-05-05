import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - ViewModel

@MainActor
@Observable
final class CampaignAudiencePreviewViewModel {
    private(set) var preview: CampaignAudiencePreview?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let api: APIClient
    let campaignId: Int

    init(api: APIClient, campaignId: Int) {
        self.api = api
        self.campaignId = campaignId
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            preview = try await api.previewCampaignAudience(id: campaignId)
        } catch {
            AppLog.ui.error(
                "Audience preview failed: \(error.localizedDescription, privacy: .public)"
            )
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - View

/// Read-only audience preview: total eligible recipients + up to 3 sample messages.
public struct CampaignAudiencePreviewView: View {
    @State private var vm: CampaignAudiencePreviewViewModel
    @Environment(\.dismiss) private var dismiss

    public init(api: APIClient, campaignId: Int) {
        _vm = State(wrappedValue: CampaignAudiencePreviewViewModel(api: api, campaignId: campaignId))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                bodyContent
            }
            .navigationTitle("Audience Preview")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .task { await vm.load() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await vm.load() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh preview")
                    .disabled(vm.isLoading)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var bodyContent: some View {
        if vm.isLoading {
            ProgressView("Calculating…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage {
            errorPane(err)
        } else if let preview = vm.preview {
            previewContent(preview)
        }
    }

    private func previewContent(_ preview: CampaignAudiencePreview) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                // Total count card
                HStack(spacing: BrandSpacing.lg) {
                    VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                        Text("Total eligible")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                        Text("\(preview.totalRecipients)")
                            .font(.brandHeadlineLarge())
                            .foregroundStyle(.bizarreOnSurface)
                            .monospacedDigit()
                    }
                    Spacer()
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.bizarreOrange)
                        .accessibilityHidden(true)
                }
                .padding(BrandSpacing.lg)
                .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Total eligible recipients: \(preview.totalRecipients)")

                if !preview.preview.isEmpty {
                    VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                        Text("Sample messages")
                            .font(.brandTitleSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .accessibilityAddTraits(.isHeader)

                        ForEach(preview.preview) { recipient in
                            SampleMessageBubble(recipient: recipient)
                        }
                    }
                }

                Text("TCPA note: Only customers who have opted in to this channel will receive this campaign.")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.leading)
                    .padding(.top, BrandSpacing.xs)
            }
            .padding(BrandSpacing.base)
        }
    }

    private func errorPane(_ msg: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36)).foregroundStyle(.bizarreError).accessibilityHidden(true)
            Text("Preview unavailable").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
            Text(msg).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent).tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Sample bubble

private struct SampleMessageBubble: View {
    let recipient: PreviewRecipient

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            HStack {
                Image(systemName: "person.circle.fill")
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityHidden(true)
                Text(recipient.firstName ?? "Customer #\(recipient.customerId)")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
            }
            Text(recipient.renderedBody)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .padding(BrandSpacing.md)
                .background(Color.bizarreSurface2, in: RoundedRectangle(cornerRadius: 10))
                .textSelection(.enabled)
        }
        .padding(BrandSpacing.sm)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sample for \(recipient.firstName ?? "customer"): \(recipient.renderedBody)")
    }
}
