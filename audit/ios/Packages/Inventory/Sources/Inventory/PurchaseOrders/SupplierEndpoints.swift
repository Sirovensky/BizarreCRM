import Foundation
import Networking

// MARK: - APIClient + Supplier endpoints

public extension APIClient {

    func listSuppliers() async throws -> [Supplier] {
        try await get("/api/v1/suppliers", as: [Supplier].self)
    }

    func getSupplier(id: Int64) async throws -> Supplier {
        try await get("/api/v1/suppliers/\(id)", as: Supplier.self)
    }

    func createSupplier(_ body: SupplierRequest) async throws -> Supplier {
        try await post("/api/v1/suppliers", body: body, as: Supplier.self)
    }

    func updateSupplier(id: Int64, _ body: SupplierRequest) async throws -> Supplier {
        try await put("/api/v1/suppliers/\(id)", body: body, as: Supplier.self)
    }

    func deleteSupplier(id: Int64) async throws {
        try await delete("/api/v1/suppliers/\(id)")
    }
}

// MARK: - Request body

public struct SupplierRequest: Encodable, Sendable {
    public let name: String
    public let contactName: String?
    public let email: String
    public let phone: String
    public let address: String
    public let paymentTerms: String
    public let leadTimeDays: Int

    public init(
        name: String,
        contactName: String?,
        email: String,
        phone: String,
        address: String,
        paymentTerms: String,
        leadTimeDays: Int
    ) {
        self.name = name
        self.contactName = contactName
        self.email = email
        self.phone = phone
        self.address = address
        self.paymentTerms = paymentTerms
        self.leadTimeDays = leadTimeDays
    }

    enum CodingKeys: String, CodingKey {
        case name
        case contactName  = "contact_name"
        case email
        case phone
        case address
        case paymentTerms = "payment_terms"
        case leadTimeDays = "lead_time_days"
    }
}
