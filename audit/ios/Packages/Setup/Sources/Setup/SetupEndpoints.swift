import Foundation
import Networking

// MARK: - Server models

public struct SetupStatusResponse: Decodable, Sendable {
    public let currentStep: Int
    public let completed: [Int]
    public let totalSteps: Int
}

public struct SetupStepResponse: Decodable, Sendable {
    public let nextStep: Int
}

public struct SetupCompleteResponse: Decodable, Sendable {
    public let ok: Bool
}

// MARK: - Request payloads

public struct SetupStepPayload: Encodable, Sendable {
    public let data: [String: String]

    public init(data: [String: String]) {
        self.data = data
    }

    // Encode as flat key-value pairs
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)
        for (key, value) in data {
            try container.encode(value, forKey: StringCodingKey(key))
        }
    }
}

private struct StringCodingKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

// MARK: - Logo upload wire types

private struct SetupLogoBody: Encodable, Sendable {
    let imageBase64: String
    let mimeType: String
    enum CodingKeys: String, CodingKey {
        case imageBase64 = "image_base64"
        case mimeType    = "mime_type"
    }
}

public struct SetupLogoResponse: Decodable, Sendable {
    public let url: String?
}

// MARK: - APIClient extension

public extension APIClient {
    func getSetupStatus() async throws -> SetupStatusResponse {
        try await get("setup/status", as: SetupStatusResponse.self)
    }

    func submitSetupStep(_ step: Int, payload: SetupStepPayload) async throws -> SetupStepResponse {
        try await post("setup/step/\(step)", body: payload, as: SetupStepResponse.self)
    }

    func completeSetup() async throws -> SetupCompleteResponse {
        try await post("setup/complete", body: SetupStepPayload(data: [:]), as: SetupCompleteResponse.self)
    }

    /// Uploads the tenant logo as base64 JSON to `POST /api/v1/setup/logo`.
    /// Returns the CDN URL of the persisted logo.
    func uploadSetupLogo(_ imageData: Data, mimeType: String = "image/jpeg") async throws -> SetupLogoResponse {
        let body = SetupLogoBody(imageBase64: imageData.base64EncodedString(), mimeType: mimeType)
        return try await post("setup/logo", body: body, as: SetupLogoResponse.self)
    }
}
