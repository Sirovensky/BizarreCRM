import Foundation
import CoreLocation
import Networking

// MARK: - Request / Response

public struct SignOffRequest: Encodable, Sendable {
    public let signaturePng: String   // base-64 encoded PNG
    public let disclaimer: String
    public let signedAt: String       // ISO-8601

    enum CodingKeys: String, CodingKey {
        case signaturePng = "signaturePng"
        case disclaimer
        case signedAt = "signedAt"
    }
}

public struct SignOffResponse: Decodable, Sendable {
    public let receiptId: String
    public let pdfUrl: String?

    enum CodingKeys: String, CodingKey {
        case receiptId = "receiptId"
        case pdfUrl = "pdfUrl"
    }
}

// MARK: - ViewModel

@Observable
@MainActor
public final class TicketSignOffViewModel: Sendable {

    public enum State: Sendable, Equatable {
        case idle
        case submitting
        case success(receiptId: String, pdfURL: URL?)
        case failed(String)
    }

    public static let disclaimerText =
        "I accept the repair and confirm the device works as expected. " +
        "By signing below, I acknowledge receipt of my device and authorize " +
        "BizarreCRM to charge the agreed amount."

    public private(set) var state: State = .idle
    /// Base-64 encoded PNG of the captured signature.
    public var signatureData: Data?
    public var gpsLocation: CLLocationCoordinate2D?

    private let ticketId: Int64
    private let api: APIClient
    private let locationManager: CLLocationManager

    public init(ticketId: Int64, api: APIClient) {
        self.ticketId = ticketId
        self.api = api
        self.locationManager = CLLocationManager()
    }

    // MARK: - GPS

    public func requestLocationIfAllowed() {
        let status = locationManager.authorizationStatus
        let allowed: Bool
        #if os(iOS)
        allowed = (status == .authorizedWhenInUse || status == .authorizedAlways)
        #else
        allowed = (status == .authorized || status == .authorizedAlways)
        #endif
        if allowed {
            locationManager.requestLocation()
            if let loc = locationManager.location {
                gpsLocation = loc.coordinate
            }
        }
    }

    // MARK: - Submit

    public func submit() async {
        guard let data = signatureData, !data.isEmpty else {
            state = .failed("Please sign before submitting.")
            return
        }
        state = .submitting
        do {
            let b64 = data.base64EncodedString()
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            let now = formatter.string(from: Date())
            let req = SignOffRequest(
                signaturePng: b64,
                disclaimer: Self.disclaimerText,
                signedAt: now
            )
            let response = try await api.post(
                "/api/v1/tickets/\(ticketId)/sign-off",
                body: req,
                as: SignOffResponse.self
            )
            let pdfURL = response.pdfUrl.flatMap { URL(string: $0) }
            state = .success(receiptId: response.receiptId, pdfURL: pdfURL)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Clear

    public func clearSignature() {
        signatureData = nil
        if case .failed = state { state = .idle }
    }
}
