import Foundation
import Networking

// MARK: - Protocol

/// §16 — Repository protocol for coupon code management.
///
/// All calls go through `APIClient+CashRegister` typed wrappers (§20 containment).
public protocol CouponRepository: Sendable {
    /// `GET /api/v1/coupons` — list all coupon codes.
    func listCoupons() async throws -> [CouponCode]

    /// `POST /api/v1/coupons/batch` — batch-generate coupon codes.
    func batchGenerate(request: BatchGenerateCouponsRequest) async throws -> [CouponCode]

    /// `PATCH /api/v1/coupons/:id` — mark a coupon expired (sets `expires_at` to now).
    func markExpired(couponId: String) async throws -> CouponCode

    /// `DELETE /api/v1/coupons/:id` — delete a coupon.
    func deleteCoupon(id: String) async throws
}

// MARK: - Production implementation

/// §16 — Live `CouponRepository` backed by `APIClient+CashRegister` wrappers.
public struct CouponRepositoryImpl: CouponRepository {

    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func listCoupons() async throws -> [CouponCode] {
        try await api.listCoupons(as: [CouponCode].self)
    }

    public func batchGenerate(request: BatchGenerateCouponsRequest) async throws -> [CouponCode] {
        try await api.batchGenerateCoupons(body: request, as: [CouponCode].self)
    }

    public func markExpired(couponId: String) async throws -> CouponCode {
        struct ExpireBody: Codable, Sendable {
            let expiresAt: String
            enum CodingKeys: String, CodingKey { case expiresAt = "expires_at" }
        }
        let body = ExpireBody(expiresAt: ISO8601DateFormatter().string(from: .now))
        return try await api.patchCoupon(id: couponId, body: body, as: CouponCode.self)
    }

    public func deleteCoupon(id: String) async throws {
        try await api.deleteCoupon(id: id)
    }
}
