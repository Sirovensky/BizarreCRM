import Foundation

// MARK: - Customer mutations — extended responses
//
// Server routes (packages/server/src/routes/customers.routes.ts):
//   PUT /:id — update customer, returns full refreshed CustomerDetail row
//
// updateCustomer(id:_:) → CreatedResource lives in CreateEndpoints.swift and is
// kept there for backwards-compat. The overload here returns the full
// CustomerDetail for callers that need to refresh in-place after an edit.

public extension APIClient {

    /// `PUT /api/v1/customers/:id` — returns the full refreshed `CustomerDetail`.
    ///
    /// Prefer this over `updateCustomer(id:_:)` in `CreateEndpoints.swift` when
    /// the caller needs to update its in-memory snapshot without a follow-up GET.
    func updateCustomerDetail(id: Int64, _ req: UpdateCustomerRequest) async throws -> CustomerDetail {
        try await put("/api/v1/customers/\(id)", body: req, as: CustomerDetail.self)
    }
}
