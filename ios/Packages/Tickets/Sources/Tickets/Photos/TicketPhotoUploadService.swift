import Foundation
import Networking

// MARK: - Upload item

public struct PhotoUploadItem: Identifiable, Sendable {
    public let id: UUID
    public let localURL: URL
    public let ticketId: Int64

    public init(localURL: URL, ticketId: Int64) {
        self.id = UUID()
        self.localURL = localURL
        self.ticketId = ticketId
    }
}

public struct PhotoUploadResult: Decodable, Sendable {
    public let photoId: Int64?
    public let url: String?

    enum CodingKeys: String, CodingKey {
        case photoId = "id"
        case url
    }
}

// MARK: - Upload state

public enum PhotoUploadState: Sendable {
    case queued
    case uploading(progress: Double)
    case done(url: String)
    case failed(String)
}

// MARK: - Service actor

/// Uploads ticket photos via `POST /api/v1/tickets/:id/photos` (multipart).
/// Maintains an offline queue — failed items are retried on demand.
public actor TicketPhotoUploadService {

    private var queue: [PhotoUploadItem] = []
    private(set) var states: [UUID: PhotoUploadState] = [:]
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    // MARK: - Enqueue

    public func enqueue(_ item: PhotoUploadItem) async {
        queue.append(item)
        states[item.id] = .queued
        await performUpload(item)
    }

    // MARK: - Retry failed

    public func retryFailed() async {
        let failed = queue.filter {
            if case .failed = states[$0.id] { return true }
            return false
        }
        for item in failed {
            await performUpload(item)
        }
    }

    // MARK: - State accessor

    public func state(for id: UUID) -> PhotoUploadState? {
        states[id]
    }

    // MARK: - Upload

    private func performUpload(_ item: PhotoUploadItem) async {
        states[item.id] = .uploading(progress: 0)
        do {
            let data = try Data(contentsOf: item.localURL)
            let boundary = UUID().uuidString
            let body = buildMultipartBody(data: data, fileName: item.localURL.lastPathComponent, boundary: boundary)

            guard let baseURL = await api.currentBaseURL() else {
                throw PhotoUploadError.noBaseURL
            }
            let url = baseURL.appendingPathComponent("/api/v1/tickets/\(item.ticketId)/photos")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.httpBody = body

            // Use background URLSession for upload — survives app suspension.
            let sessionConfig = URLSessionConfiguration.background(withIdentifier: "com.bizarrecrm.photos.\(item.id)")
            sessionConfig.waitsForConnectivity = true
            let session = URLSession(configuration: sessionConfig)

            states[item.id] = .uploading(progress: 0.5)
            let (respData, _) = try await session.data(for: request)
            let decoded = try JSONDecoder().decode(PhotoUploadResult.self, from: respData)
            states[item.id] = .done(url: decoded.url ?? "")
            // Remove from queue on success
            queue.removeAll { $0.id == item.id }
        } catch {
            states[item.id] = .failed(error.localizedDescription)
        }
    }

    // MARK: - Multipart builder

    private func buildMultipartBody(data: Data, fileName: String, boundary: String) -> Data {
        var body = Data()
        let nl = "\r\n"
        func str(_ s: String) { body.append(Data(s.utf8)) }
        str("--\(boundary)\(nl)")
        str("Content-Disposition: form-data; name=\"photos\"; filename=\"\(fileName)\"\(nl)")
        str("Content-Type: image/jpeg\(nl)\(nl)")
        body.append(data)
        str("\(nl)--\(boundary)--\(nl)")
        return body
    }
}

// MARK: - Errors

public enum PhotoUploadError: LocalizedError {
    case noBaseURL
    case invalidData

    public var errorDescription: String? {
        switch self {
        case .noBaseURL: return "Server URL not configured."
        case .invalidData: return "Could not read photo data."
        }
    }
}
