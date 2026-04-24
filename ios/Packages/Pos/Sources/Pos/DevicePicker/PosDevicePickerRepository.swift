import Foundation
import Networking

// MARK: - Minimal mirror of customer_assets row
//
// We cannot import from the Customers package's CustomerAsset type without
// a Package.swift export that another agent owns. This private struct mirrors
// the exact DB columns returned by GET /api/v1/customers/:id/assets.

private struct AssetRow: Decodable, Sendable {
    let id: Int64
    let name: String
    let deviceType: String?
    let serial: String?
    let imei: String?
    let color: String?

    enum CodingKeys: String, CodingKey {
        case id, name, serial, imei, color
        case deviceType = "device_type"
    }

    /// Builds a descriptive subtitle from available fields.
    var subtitle: String? {
        var parts: [String] = []
        if let dt = deviceType, !dt.isEmpty { parts.append(dt) }
        if let s = serial, !s.isEmpty { parts.append("S/N \(s)") }
        if let i = imei, !i.isEmpty { parts.append("IMEI \(i)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: - Protocol

/// Fetches the customer's saved devices and maps them to `PosDeviceOption`s.
/// Always appends `.noSpecificDevice` and `.addNew` so the picker is never
/// empty even when the customer has no registered assets.
public protocol PosDevicePickerRepository: Sendable {
    func fetchAssets(customerId: Int64) async throws -> [PosDeviceOption]
}

// MARK: - Implementation

public struct PosDevicePickerRepositoryImpl: PosDevicePickerRepository {

    private let api: any APIClient

    public init(api: any APIClient) {
        self.api = api
    }

    public func fetchAssets(customerId: Int64) async throws -> [PosDeviceOption] {
        let rows = try await api.get(
            "/api/v1/customers/\(customerId)/assets",
            as: [AssetRow].self
        )

        var options: [PosDeviceOption] = rows.map { row in
            .asset(id: row.id, label: row.name, subtitle: row.subtitle)
        }

        // Sentinel rows are always appended in a fixed order.
        options.append(.noSpecificDevice)
        options.append(.addNew)

        return options
    }
}
