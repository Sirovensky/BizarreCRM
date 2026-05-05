import Foundation
import Networking

// MARK: - §43.5 Device Template Editor API Wrappers

public extension APIClient {

    /// POST /device-templates
    func createDeviceTemplate(body: CreateDeviceTemplateRequest) async throws -> DeviceTemplate {
        try await post("/api/v1/device-templates", body: body, as: DeviceTemplate.self)
    }

    /// PATCH /device-templates/:id
    func updateDeviceTemplate(id: Int64, body: UpdateDeviceTemplateRequest) async throws -> DeviceTemplate {
        try await patch("/api/v1/device-templates/\(id)", body: body, as: DeviceTemplate.self)
    }

    /// DELETE /device-templates/:id
    func deleteDeviceTemplate(id: Int64) async throws {
        try await delete("/api/v1/device-templates/\(id)")
    }
}
