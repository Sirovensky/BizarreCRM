import Foundation
#if canImport(UIKit)
import UIKit
#endif
import CoreImage
import CoreImage.CIFilterBuiltins
import Networking

// MARK: - ReferralService

public actor ReferralService {
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    // MARK: - Public interface

    /// Fetch the existing referral code for `customerId`, or generate a new one.
    public func getOrGenerateCode(customerId: String) async throws -> ReferralCode {
        try await api.get("referrals/code/\(customerId)", as: ReferralCode.self)
    }

    /// Build a universal (https) share link embedding the code.
    /// Format: `https://app.bizarrecrm.com/signup?ref=<code>`
    /// The URL also works as a custom-scheme deep link via universal links.
    public func generateShareLink(code: String) -> URL {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "app.bizarrecrm.com"
        comps.path = "/signup"
        comps.queryItems = [URLQueryItem(name: "ref", value: code)]
        // Force-unwrap: statically-valid URL components
        return comps.url!
    }

#if canImport(UIKit)
    /// Generate a QR code UIImage encoding `bizarrecrm://signup?ref=<code>`.
    /// Falls back to the https URL string for scanners that don't handle custom schemes.
    public func generateQR(code: String) -> UIImage? {
        let urlString = "bizarrecrm://signup?ref=\(code)"
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        guard let data = urlString.data(using: .utf8) else { return nil }
        filter.message = data
        filter.correctionLevel = "M"

        guard let ciImage = filter.outputImage else { return nil }
        // Scale up 10× so the QR is crisp at display size
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
#endif

    // MARK: - Leaderboard

    public func fetchLeaderboard() async throws -> [ReferralLeaderEntry] {
        let response = try await api.get("referrals/leaderboard", as: ReferralLeaderboardResponse.self)
        return response.entries
    }
}
