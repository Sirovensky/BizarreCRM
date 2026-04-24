import Foundation
import Networking

// MARK: - Batch upload item

/// A single photo destined for `POST /tickets/:id/photos`.
public struct BatchPhotoItem: Identifiable, Sendable {
    public let id: UUID
    public let imageData: Data
    /// JPEG filename that will appear in the multipart part.
    public let fileName: String
    public let ticketId: Int64
    public let ticketDeviceId: Int64
    /// "pre" or "post" tagging for before/after classification.
    public let photoType: String

    public init(
        imageData: Data,
        fileName: String,
        ticketId: Int64,
        ticketDeviceId: Int64,
        photoType: String = "pre"
    ) {
        self.id = UUID()
        self.imageData = imageData
        self.fileName = fileName
        self.ticketId = ticketId
        self.ticketDeviceId = ticketDeviceId
        self.photoType = photoType
    }
}

// MARK: - Per-item progress

public enum BatchItemProgress: Sendable, Equatable {
    case pending
    case uploading(fraction: Double)
    case done(remoteURL: String)
    case failed(reason: String)
}

// MARK: - Batch result

public struct BatchUploadResult: Sendable {
    public let succeeded: [UUID: String]   // id → remote URL
    public let failed: [UUID: String]      // id → error reason
}

// MARK: - Actor

/// Coordinates concurrent batch uploads with per-item progress reporting.
/// Route confirmed: `POST /tickets/:id/photos` (tickets.routes.ts:2431).
public actor TicketPhotoBatchUploader {

    // MARK: State

    private(set) public var progress: [UUID: BatchItemProgress] = [:]

    private let api: APIClient
    /// Maximum concurrent uploads (default 3 to avoid saturating the connection).
    private let maxConcurrency: Int

    public init(api: APIClient, maxConcurrency: Int = 3) {
        self.api = api
        self.maxConcurrency = maxConcurrency
    }

    // MARK: - Public API

    /// Uploads all items, honouring `maxConcurrency`. Returns a summary result.
    public func uploadBatch(_ items: [BatchPhotoItem]) async -> BatchUploadResult {
        // Initialise all items as pending
        for item in items {
            progress[item.id] = .pending
        }

        var succeeded: [UUID: String] = [:]
        var failed: [UUID: String] = [:]

        // Process in concurrency-limited windows
        var index = 0
        while index < items.count {
            let slice = items[index ..< min(index + maxConcurrency, items.count)]
            await withTaskGroup(of: (UUID, BatchItemProgress).self) { group in
                for item in slice {
                    group.addTask { [self] in
                        await self.uploadItem(item)
                    }
                }
                for await (id, result) in group {
                    progress[id] = result
                    switch result {
                    case .done(let url):
                        succeeded[id] = url
                    case .failed(let reason):
                        failed[id] = reason
                    default:
                        break
                    }
                }
            }
            index += maxConcurrency
        }

        return BatchUploadResult(succeeded: succeeded, failed: failed)
    }

    /// Returns the current progress for a specific item.
    public func itemProgress(for id: UUID) -> BatchItemProgress? {
        progress[id]
    }

    // MARK: - Private upload

    private func uploadItem(_ item: BatchPhotoItem) async -> (UUID, BatchItemProgress) {
        progress[item.id] = .uploading(fraction: 0.0)

        guard let baseURL = await api.currentBaseURL() else {
            return (item.id, .failed(reason: "Server URL not configured."))
        }

        let endpoint = baseURL.appendingPathComponent("/api/v1/tickets/\(item.ticketId)/photos")
        let boundary = UUID().uuidString
        let body = buildMultipart(item: item, boundary: boundary)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = body

        progress[item.id] = .uploading(fraction: 0.5)

        do {
            let sessionConfig = URLSessionConfiguration.background(
                withIdentifier: "com.bizarrecrm.batch.\(item.id)"
            )
            sessionConfig.waitsForConnectivity = true
            let session = URLSession(configuration: sessionConfig)

            let (data, response) = try await session.data(for: request)

            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode >= 400 {
                let msg = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
                return (item.id, .failed(reason: msg))
            }

            struct UploadedPhoto: Decodable {
                let url: String?
            }
            struct UploadEnvelope: Decodable {
                let success: Bool
                let data: [UploadedPhoto]?
            }
            let envelope = try JSONDecoder().decode(UploadEnvelope.self, from: data)
            let remoteURL = envelope.data?.first?.url ?? ""
            return (item.id, .done(remoteURL: remoteURL))
        } catch {
            return (item.id, .failed(reason: error.localizedDescription))
        }
    }

    // MARK: - Multipart builder

    private func buildMultipart(item: BatchPhotoItem, boundary: String) -> Data {
        var body = Data()
        let nl = "\r\n"
        func str(_ s: String) { body.append(Data(s.utf8)) }
        str("--\(boundary)\(nl)")
        str("Content-Disposition: form-data; name=\"photos\"; filename=\"\(item.fileName)\"\(nl)")
        str("Content-Type: image/jpeg\(nl)")
        str("Content-Length: \(item.imageData.count)\(nl)\(nl)")
        body.append(item.imageData)
        str("\(nl)")
        // type field
        str("--\(boundary)\(nl)")
        str("Content-Disposition: form-data; name=\"type\"\(nl)\(nl)")
        str(item.photoType)
        str("\(nl)--\(boundary)--\(nl)")
        return body
    }
}
