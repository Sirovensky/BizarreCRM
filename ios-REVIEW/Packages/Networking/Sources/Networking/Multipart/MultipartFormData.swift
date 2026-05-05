import Foundation

// MARK: - MultipartFormData
//
// Pure value-type builder for multipart/form-data payloads (RFC 7578).
// Call appendField / appendFile to add parts, then encode() to get the
// raw Data + boundary string suitable for a URLRequest body.
//
// Usage:
//   var form = MultipartFormData()
//   form.appendField(name: "title", value: "My Document")
//   form.appendFile(name: "file", filename: "photo.jpg", mimeType: "image/jpeg", data: jpegData)
//   let (body, contentType) = form.encode()
//   // contentType == "multipart/form-data; boundary=<uuid>"

public struct MultipartFormData: Sendable {

    // MARK: Internal part representation

    private enum Part: Sendable {
        case field(name: String, value: String)
        case file(name: String, filename: String, mimeType: String, data: Data)
    }

    // MARK: State

    /// Boundary string; fixed at construction so encode() is idempotent.
    public let boundary: String

    private var parts: [Part]

    // MARK: Init

    public init(boundary: String = UUID().uuidString) {
        self.boundary = boundary
        self.parts = []
    }

    // MARK: Append helpers (value-type — each returns a new copy)

    /// Returns a new MultipartFormData with a plain text field appended.
    public func appendingField(name: String, value: String) -> MultipartFormData {
        var copy = self
        copy.parts.append(.field(name: name, value: value))
        return copy
    }

    /// Returns a new MultipartFormData with a file part appended.
    public func appendingFile(
        name: String,
        filename: String,
        mimeType: String,
        data: Data
    ) -> MultipartFormData {
        var copy = self
        copy.parts.append(.file(name: name, filename: filename, mimeType: mimeType, data: data))
        return copy
    }

    // MARK: Mutating convenience wrappers

    /// Appends a plain text field in place.
    public mutating func appendField(name: String, value: String) {
        parts.append(.field(name: name, value: value))
    }

    /// Appends a file part in place.
    public mutating func appendFile(
        name: String,
        filename: String,
        mimeType: String,
        data: Data
    ) {
        parts.append(.file(name: name, filename: filename, mimeType: mimeType, data: data))
    }

    // MARK: Encode

    /// Encodes all parts into a multipart/form-data body.
    ///
    /// - Returns: `(body: Data, contentTypeHeaderValue: String)` where the
    ///   header value is ready to be set on `Content-Type`.
    public func encode() -> (body: Data, contentTypeHeaderValue: String) {
        var body = Data()
        let crlf = "\r\n"
        let boundaryPrefix = "--\(boundary)"

        for part in parts {
            body.appendString("\(boundaryPrefix)\(crlf)")

            switch part {
            case let .field(name, value):
                body.appendString("Content-Disposition: form-data; name=\"\(name)\"\(crlf)")
                body.appendString(crlf)
                body.appendString(value)
                body.appendString(crlf)

            case let .file(name, filename, mimeType, data):
                body.appendString(
                    "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\(crlf)"
                )
                body.appendString("Content-Type: \(mimeType)\(crlf)")
                body.appendString(crlf)
                body.append(data)
                body.appendString(crlf)
            }
        }

        body.appendString("\(boundaryPrefix)--\(crlf)")

        let contentTypeHeaderValue = "multipart/form-data; boundary=\(boundary)"
        return (body, contentTypeHeaderValue)
    }
}

// MARK: - Data helper

private extension Data {
    mutating func appendString(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
