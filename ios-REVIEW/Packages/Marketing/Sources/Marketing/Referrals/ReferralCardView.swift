import SwiftUI
import DesignSystem
import Core
#if canImport(UIKit)
import UIKit
#endif

// MARK: - ReferralCardViewModel

@Observable
@MainActor
public final class ReferralCardViewModel {
    public var referralCode: ReferralCode?
    #if canImport(UIKit)
    public var qrImage: UIImage?
    #endif
    public var isLoading = false
    public var errorMessage: String?

    private let customerId: String
    private let service: ReferralService

    public init(customerId: String, service: ReferralService) {
        self.customerId = customerId
        self.service = service
    }

    public func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let code = try await service.getOrGenerateCode(customerId: customerId)
            referralCode = code
            #if canImport(UIKit)
            qrImage = await service.generateQR(code: code.code)
            #endif
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    public func shareLink() async -> URL? {
        guard let code = referralCode else { return nil }
        return await service.generateShareLink(code: code.code)
    }
}

// MARK: - ReferralCardView

/// Shown in CustomerDetailView — big code + QR + Share button.
public struct ReferralCardView: View {
    @State private var vm: ReferralCardViewModel
    @State private var shareItems: [Any] = []
    @State private var isShowingShare = false

    public init(customerId: String, service: ReferralService) {
        _vm = State(initialValue: ReferralCardViewModel(customerId: customerId, service: service))
    }

    public var body: some View {
        Group {
            if vm.isLoading {
                loadingView
            } else if let error = vm.errorMessage {
                errorView(message: error)
            } else if let code = vm.referralCode {
                codeView(code: code)
            } else {
                EmptyView()
            }
        }
        .task { await vm.load() }
    }

    // MARK: - Loading

    private var loadingView: some View {
        ProgressView("Loading referral code…")
            .frame(maxWidth: .infinity, minHeight: 180)
            .accessibilityLabel("Loading referral code")
    }

    // MARK: - Error

    private func errorView(message: String) -> some View {
        VStack(spacing: BrandSpacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.bizarreError)
            Text(message)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Button("Retry") { Task { await vm.load() } }
                .buttonStyle(.brandGlass)
        }
        .padding(BrandSpacing.base)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Code card

    private func codeView(code: ReferralCode) -> some View {
        VStack(spacing: BrandSpacing.lg) {
            headerSection(code: code)
            #if canImport(UIKit)
            if let qr = vm.qrImage {
                qrSection(image: qr, code: code)
            }
            #endif
            statsRow(code: code)
            shareButton(code: code)
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    private func headerSection(code: ReferralCode) -> some View {
        VStack(spacing: BrandSpacing.xs) {
            Text("Your Referral Code")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)

            Text(code.code)
                .font(.brandMono(size: 28))
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityLabel("Referral code: \(code.code)")
                .textSelection(.enabled)
        }
    }

    #if canImport(UIKit)
    private func qrSection(image: UIImage, code: ReferralCode) -> some View {
        Image(uiImage: image)
            .interpolation(.none)
            .resizable()
            .scaledToFit()
            .frame(width: 160, height: 160)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
            .accessibilityLabel("QR code for referral code \(code.code)")
    }
    #endif

    private func statsRow(code: ReferralCode) -> some View {
        HStack(spacing: BrandSpacing.xl) {
            statItem(label: "Uses", value: "\(code.uses)")
            statItem(label: "Conversions", value: "\(code.conversions)")
        }
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(spacing: BrandSpacing.xxs) {
            Text(value)
                .font(.brandHeadlineMedium())
                .foregroundStyle(.bizarreOnSurface)
                .monospacedDigit()
            Text(label)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    private func shareButton(code: ReferralCode) -> some View {
        Button {
            Task {
                if let url = await vm.shareLink() {
                    let msg = "Use my referral code \(code.code) to sign up: \(url.absoluteString)"
                    shareItems = [msg, url]
                    isShowingShare = true
                }
            }
        } label: {
            Label("Share Code", systemImage: "square.and.arrow.up")
                .font(.brandTitleSmall())
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.brandGlassProminent)
        .tint(.bizarreOrange)
        .accessibilityLabel("Share referral code \(code.code)")
        #if canImport(UIKit)
        .sheet(isPresented: $isShowingShare) {
            ActivityView(items: shareItems)
                .presentationDetents([.medium, .large])
        }
        #endif
    }
}

// MARK: - ActivityView

#if canImport(UIKit)
/// Thin UIActivityViewController wrapper.
private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
#endif
