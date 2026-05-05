import Foundation

// MARK: - URLRequest + Multipart integration helper
//
// Convenience extension that applies a MultipartFormData body to a URLRequest.
// This is the glue layer between the value-type builder and URLSession.
//
// Usage:
//   var request = URLRequest(url: url)
//   request.httpMethod = "POST"
//   let (body, contentTypeValue) = request.applyMultipartForm(form)
//   // request is now ready for URLSession.dataTask or MultipartUploadService.upload

public extension URLRequest {

    /// Encodes `form` and writes its body + Content-Type header into the receiver.
    ///
    /// - Parameter form: A fully-assembled `MultipartFormData`.
    /// - Parameter authToken: Optional Bearer token added to `Authorization`.
    /// - Returns: The encoded body `Data` (also stored in `httpBody`).
    @discardableResult
    mutating func applyMultipartForm(
        _ form: MultipartFormData,
        authToken: String? = nil
    ) -> Data {
        let (body, contentTypeValue) = form.encode()
        self.httpBody = body
        self.setValue(contentTypeValue, forHTTPHeaderField: "Content-Type")
        self.setValue(String(body.count), forHTTPHeaderField: "Content-Length")
        if let token = authToken {
            self.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return body
    }

    /// Returns a new URLRequest with the multipart form applied (non-mutating variant).
    func applyingMultipartForm(
        _ form: MultipartFormData,
        authToken: String? = nil
    ) -> (request: URLRequest, body: Data) {
        var copy = self
        let body = copy.applyMultipartForm(form, authToken: authToken)
        return (copy, body)
    }
}
