import Foundation
import Networking

// §7.11 Invoice Template CRUD endpoints

public extension APIClient {

    /// `GET /api/v1/invoice-templates`
    func listInvoiceTemplates() async throws -> [InvoiceTemplate] {
        try await get("/api/v1/invoice-templates", query: nil, as: [InvoiceTemplate].self)
    }

    /// `GET /api/v1/invoice-templates/:id`
    func invoiceTemplate(id: Int64) async throws -> InvoiceTemplate {
        try await get("/api/v1/invoice-templates/\(id)", query: nil, as: InvoiceTemplate.self)
    }

    /// `POST /api/v1/invoice-templates`
    func createInvoiceTemplate(_ req: CreateInvoiceTemplateRequest) async throws -> InvoiceTemplate {
        try await post("/api/v1/invoice-templates", body: req, as: InvoiceTemplate.self)
    }

    /// `PUT /api/v1/invoice-templates/:id`
    func updateInvoiceTemplate(id: Int64, _ req: CreateInvoiceTemplateRequest) async throws -> InvoiceTemplate {
        try await put("/api/v1/invoice-templates/\(id)", body: req, as: InvoiceTemplate.self)
    }

    /// `DELETE /api/v1/invoice-templates/:id`
    func deleteInvoiceTemplate(id: Int64) async throws {
        try await delete("/api/v1/invoice-templates/\(id)")
    }
}
