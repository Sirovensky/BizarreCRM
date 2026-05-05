import Foundation
import Networking

// MARK: - Upload item

public struct PhotoUploadItem: Identifiable, Sendable {
    public let id: UUID
    public let localURL: URL
    public let ticketId: Int64
    /// The device this photo belongs to. The server requires `ticket_device_id`
    /// in the multipart body (tickets.routes.ts:2421).
    public let ticketDeviceId: Int64
    /// "pre" or "post" tag for before/after classification.
    public let photoType: String

    public init(localURL: URL, ticketId: Int64, ticketDeviceId: Int64 = 0, photoType: String = "pre") {
        self.id = UUID()
        self.localURL = localURL
        self.ticketId = ticketId
        self.ticketDeviceId = ticketDeviceId
        self.photoType = photoType
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
///
/// URLSession is never constructed here — all network I/O is delegated to
/// `APIClient.uploadTicketPhoto(...)` which lives in the approved Networking
/// package (§28.3 containment).
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
            let fileName = item.localURL.lastPathComponent

            states[item.id] = .uploading(progress: 0.5)

            // §28.3: URLSession construction delegated to Networking package.
            let responseData = try await api.uploadTicketPhoto(
                imageData: data,
                fileName: fileName,
                ticketId: item.ticketId,
                photoType: item.photoType,
                sessionIdentifier: "com.bizarrecrm.photos.\(item.id)"
            )

            let decoded = try JSONDecoder().decode(PhotoUploadResult.self, from: responseData)
            states[item.id] = .done(url: decoded.url ?? "")
            // Remove from queue on success
            queue.removeAll { $0.id == item.id }
        } catch {
            states[item.id] = .failed(error.localizedDescription)
        }
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
