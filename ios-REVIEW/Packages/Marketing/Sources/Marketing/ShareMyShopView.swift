import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - §37.6 Share my shop — generates short URL with intake form + reviews

// MARK: - Model

public struct ShopPublicProfile: Decodable, Sendable {
    public let shopName: String
    public let shortUrl: String
    public let intakeFormUrl: String?
    public let reviewsUrl: String?
    public let qrCodeData: String?  // base64 PNG from server

    public init(shopName: String, shortUrl: String, intakeFormUrl: String? = nil,
                reviewsUrl: String? = nil, qrCodeData: String? = nil) {
        self.shopName = shopName
        self.shortUrl = shortUrl
        self.intakeFormUrl = intakeFormUrl
        self.reviewsUrl = reviewsUrl
        self.qrCodeData = qrCodeData
    }

    enum CodingKeys: String, CodingKey {
        case shopName = "shop_name"
        case shortUrl = "short_url"
        case intakeFormUrl = "intake_form_url"
        case reviewsUrl = "reviews_url"
        case qrCodeData = "qr_code_data"
    }
}

// MARK: - Networking

extension APIClient {
    /// `GET /api/v1/tenant/public-profile` — shop public page info.
    public func shopPublicProfile() async throws -> ShopPublicProfile {
        try await get("/api/v1/tenant/public-profile", as: ShopPublicProfile.self)
    }
}

// MARK: - ViewModel

@MainActor
@Observable
public final class ShareMyShopViewModel {
    public private(set) var profile: ShopPublicProfile?
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?

    @ObservationIgnored private let api: APIClient
    public init(api: APIClient) { self.api = api }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            profile = try await api.shopPublicProfile()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - View

#if canImport(UIKit)
import UIKit

public struct ShareMyShopView: View {
    @State private var vm: ShareMyShopViewModel
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
        _vm = State(wrappedValue: ShareMyShopViewModel(api: api))
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            Group {
                if vm.isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = vm.errorMessage {
                    errorView(err)
                } else if let p = vm.profile {
                    profileContent(p)
                }
            }
        }
        .navigationTitle("Share My Shop")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }

    @ViewBuilder
    private func profileContent(_ p: ShopPublicProfile) -> some View {
        ScrollView {
            VStack(spacing: BrandSpacing.lg) {
                // QR code (generated locally if server didn't send one)
                qrCard(p)

                // URL card
                linkCard(title: "Shop Page", url: p.shortUrl, icon: "link")

                if let intake = p.intakeFormUrl {
                    linkCard(title: "Intake Form", url: intake, icon: "doc.badge.plus")
                }

                if let reviews = p.reviewsUrl {
                    linkCard(title: "Reviews", url: reviews, icon: "star")
                }

                // Share all button
                Button {
                    shareAll(p)
                } label: {
                    Label("Share Shop Link", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
                .accessibilityLabel("Share shop link via iOS share sheet")
            }
            .padding(BrandSpacing.base)
        }
    }

    // MARK: QR code card

    private func qrCard(_ p: ShopPublicProfile) -> some View {
        VStack(spacing: BrandSpacing.md) {
            if let qrImage = generateQR(from: p.shortUrl) {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .padding(BrandSpacing.sm)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("QR code for \(p.shortUrl)")
            }
            Text(p.shopName)
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text(p.shortUrl)
                .font(.brandMono(size: 13))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity)
        .padding(BrandSpacing.lg)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.bizarreOutline.opacity(0.3), lineWidth: 0.5))
    }

    // MARK: Link card

    private func linkCard(title: String, url: String, icon: String) -> some View {
        HStack(spacing: BrandSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(.bizarreOrange)
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
                Text(url)
                    .font(.brandMono(size: 12))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 0)

            Button {
                UIPasteboard.general.string = url
            } label: {
                Image(systemName: "doc.on.clipboard")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .accessibilityLabel("Copy \(title) link")
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
        .accessibilityElement(children: .combine)
    }

    // MARK: Error view

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text(msg)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Helpers

    private func generateQR(from string: String) -> UIImage? {
        guard let data = string.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let outputImage = filter.outputImage else { return nil }
        let scale = 10.0
        let transformed = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private func shareAll(_ p: ShopPublicProfile) {
        let items: [Any] = [p.shortUrl, "Check out \(p.shopName)!"]
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = windowScene.windows.first?.rootViewController {
            root.present(vc, animated: true)
        }
    }
}
#endif
