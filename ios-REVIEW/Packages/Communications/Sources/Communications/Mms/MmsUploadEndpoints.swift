import Foundation
import Networking
import Core

// MARK: - MMS multipart upload

/// §12.2 — Attachments (image / PDF / audio) via multipart upload to MMS endpoint.
///
/// Server route: POST /api/v1/sms/send-mms (multipart/form-data)
///   Fields: to (phone), message (body text), files[] (binary parts)
///
/// Sovereignty: uploads go only to APIClient.baseURL — never a third-party CDN.
///
/// Architecture: `MmsUploadService` is an actor that holds the auth token injected
/// from the host. All multipart requests use the tenant-server base URL only.
/// SmsThreadRepositoryImpl remains the only consumer — it calls this actor instead
/// of reaching for URLSession directly.
public actor MmsUploadService {

    private let baseURL: URL
    private var authToken: String?

    public init(baseURL: URL, authToken: String? = nil) {
        self.baseURL = baseURL
        self.authToken = authToken
    }

    public func setAuthToken(_ token: String?) {
        authToken = token
    }

    // MARK: - Send MMS with attachments

    /// POST /api/v1/sms/send-mms — sends text + binary attachments.
    ///
    /// Uses `URLSession.shared` for the multipart body since `APIClient`'s protocol
    /// only exposes JSON-body methods. The request is pinned to `self.baseURL`
    /// (tenant server) with the same Bearer token set by the app on login.
    /// Sovereignty: no third-party network peer.
    public func sendMms(
        to phone: String,
        message: String,
        attachments: [MmsAttachment]
    ) async throws -> SmsMessage {
        let boundary = "BizarreMMS-\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        var body = Data()
        body.appendMultipart(boundary: boundary, name: "to",      value: phone)
        body.appendMultipart(boundary: boundary, name: "message", value: message)
        for attachment in attachments {
            guard let fileData = try? Data(contentsOf: attachment.url) else { continue }
            body.appendMultipartFile(
                boundary: boundary,
                name: "files[]",
                filename: attachment.url.lastPathComponent.isEmpty ? "attachment" : attachment.url.lastPathComponent,
                mimeType: attachment.mimeType,
                data: fileData
            )
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return try await perform(path: "/api/v1/sms/send-mms", contentType: "multipart/form-data; boundary=\(boundary)", body: body)
    }

    /// POST /api/v1/sms/send-mms — sends an AAC voice memo as a single attachment.
    public func sendVoiceMemo(to phone: String, audioURL: URL) async throws -> SmsMessage {
        guard let audioData = try? Data(contentsOf: audioURL) else {
            throw MmsUploadError.fileReadFailed
        }
        let boundary = "BizarreMMS-\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        var body = Data()
        body.appendMultipart(boundary: boundary, name: "to",      value: phone)
        body.appendMultipart(boundary: boundary, name: "message", value: "")
        body.appendMultipartFile(
            boundary: boundary,
            name: "files[]",
            filename: audioURL.lastPathComponent.isEmpty ? "voice_memo.aac" : audioURL.lastPathComponent,
            mimeType: "audio/aac",
            data: audioData
        )
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return try await perform(path: "/api/v1/sms/send-mms", contentType: "multipart/form-data; boundary=\(boundary)", body: body)
    }

    // MARK: - Private transport

    private func perform(path: String, contentType: String, body: Data) async throws -> SmsMessage {
        let url = baseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        if let origin = Self.origin(for: url) {
            req.setValue(origin, forHTTPHeaderField: "Origin")
        }
        if let token = authToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = body

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw MmsUploadError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw MmsUploadError.httpError(http.statusCode)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(APIResponse<SmsMessage>.self, from: data)
        guard let message = envelope.data else { throw MmsUploadError.noData }
        return message
    }

    private static func origin(for url: URL) -> String? {
        guard let scheme = url.scheme, let host = url.host else { return nil }
        let port = url.port.map { ":\($0)" } ?? ""
        return "\(scheme)://\(host)\(port)"
    }
}

// MARK: - Errors

public enum MmsUploadError: LocalizedError, Sendable {
    case fileReadFailed
    case invalidResponse
    case httpError(Int)
    case noData

    public var errorDescription: String? {
        switch self {
        case .fileReadFailed:     return "Could not read the attachment file."
        case .invalidResponse:    return "Invalid server response."
        case .httpError(let c):   return "Server returned HTTP \(c)."
        case .noData:             return "Server returned no message data."
        }
    }
}

// MARK: - Data multipart helpers

private extension Data {
    mutating func appendMultipart(boundary: String, name: String, value: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }

    mutating func appendMultipartFile(boundary: String, name: String, filename: String, mimeType: String, data fileData: Data) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        append(fileData)
        append("\r\n".data(using: .utf8)!)
    }
}
