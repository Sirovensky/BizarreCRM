#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// §8 Sign flow — EstimateSignSheet
//
// Staff flow: tap "Send for Signature" → sheet issues a single-use sign URL
// → URL displayed + share sheet for sending to customer via Messages/email/copy.
//
// iPhone: .presentationDetents([.medium, .large])
// iPad:   .popover from the toolbar button (caller controls)
// Glass chrome on sheet header only (CLAUDE.md rules).

public struct EstimateSignSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: EstimateSignViewModel

    private let orderId: String

    public init(estimateId: Int64, orderId: String, api: APIClient) {
        self.orderId = orderId
        _vm = State(wrappedValue: EstimateSignViewModel(estimateId: estimateId, api: api))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                        headerCard
                        if let err = vm.errorMessage {
                            errorBanner(err)
                        }
                        if let url = vm.signUrl {
                            signUrlCard(url: url)
                        } else {
                            issueButton
                        }
                    }
                    .padding(BrandSpacing.lg)
                }
            }
            .navigationTitle("Send for Signature")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityLabel("Dismiss signature sheet")
                }
            }
            .presentationDetents([.medium, .large])
            .presentationBackground(.ultraThinMaterial)
        }
    }

    // MARK: - Header card

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Label("E-Signature Link", systemImage: "pencil.and.signature")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityAddTraits(.isHeader)

            Divider()

            Text("Generate a single-use link and share it with your customer. Once they sign, the estimate status updates to \"signed\".")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .fixedSize(horizontal: false, vertical: true)

            if let expires = vm.expiresAt {
                HStack(spacing: BrandSpacing.xs) {
                    Image(systemName: "clock")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityHidden(true)
                    Text("Expires \(String(expires.prefix(10)))")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .accessibilityLabel("Link expires on \(String(expires.prefix(10)))")
            }
        }
        .padding(BrandSpacing.lg)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    // MARK: - Issue button

    private var issueButton: some View {
        Button {
            Task { await vm.issueSignUrl() }
        } label: {
            HStack(spacing: BrandSpacing.sm) {
                if vm.isIssuing {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .accessibilityHidden(true)
                }
                Text(vm.isIssuing ? "Generating link…" : "Generate Signature Link")
                    .font(.brandTitleMedium())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, BrandSpacing.md)
        }
        .buttonStyle(.borderedProminent)
        .tint(.bizarreOrange)
        .disabled(vm.isIssuing)
        .accessibilityLabel(vm.isIssuing ? "Generating link, please wait" : "Generate signature link for estimate \(orderId)")
    }

    // MARK: - Sign URL card (shown after issuance)

    private func signUrlCard(url: String) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            HStack {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text("Link Ready")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
            }
            .accessibilityLabel("Signature link is ready")

            Divider()

            Text(url)
                .font(.brandMono(size: 13))
                .foregroundStyle(.bizarreOnSurface)
                .textSelection(.enabled)
                .lineLimit(3)
                .accessibilityLabel("Signature URL: \(url)")

            Divider()

            // Share sheet via ShareLink (iOS 16+)
            ShareLink(item: url, subject: Text("Estimate Signature Link")) {
                Label("Share Link", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, BrandSpacing.sm)
            }
            .buttonStyle(.borderedProminent)
            .tint(.bizarreOrange)
            .accessibilityLabel("Share signature link with customer")

            // Copy fallback
            Button {
                UIPasteboard.general.string = url
            } label: {
                Label("Copy Link", systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, BrandSpacing.sm)
            }
            .buttonStyle(.bordered)
            .tint(.bizarreOrange)
            .accessibilityLabel("Copy signature link to clipboard")

            Text("This is a single-use link. Generating a new one will not invalidate previous links until the customer signs.")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(BrandSpacing.lg)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    // MARK: - Error banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text(message)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreError)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreError.opacity(0.1), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        .accessibilityLabel("Error: \(message)")
    }
}
#endif
