import Foundation
import Observation
import Networking
import Core

// MARK: - CouponInputState

/// The lifecycle of a coupon-apply attempt.
public enum CouponInputState: Equatable, Sendable {
    /// No attempt in flight.
    case idle
    /// Network request is in flight.
    case loading
    /// Server accepted the coupon — discount applied.
    case applied(CouponCode, discountCents: Int)
    /// Server rejected the coupon or a client-side error occurred.
    case error(String)

    public var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    public var appliedCoupon: CouponCode? {
        if case .applied(let coupon, _) = self { return coupon }
        return nil
    }

    public var discountCents: Int {
        if case .applied(_, let d) = self { return d }
        return 0
    }
}

// MARK: - CouponInputViewModel

/// Drives the `CouponInputSheet` and the coupon chip on `PosCartPanel`.
///
/// Sends `POST /coupons/apply { code, cart_id }` and expects the
/// `{ success, data: CouponApplyResponse, message }` envelope.
@MainActor
@Observable
public final class CouponInputViewModel {

    // MARK: - Published state

    /// The raw code the user typed (auto-uppercased).
    public var codeInput: String = "" {
        didSet {
            codeInput = codeInput.uppercased()
            // Clear error when user edits.
            if case .error = state { state = .idle }
        }
    }

    public private(set) var state: CouponInputState = .idle

    // MARK: - Dependencies (injected)

    private let api: APIClient
    private let cartId: () -> String

    public init(api: APIClient, cartId: @escaping () -> String) {
        self.api = api
        self.cartId = cartId
    }

    // MARK: - Computed

    public var canApply: Bool {
        !codeInput.trimmingCharacters(in: .whitespaces).isEmpty
            && !state.isLoading
            && state.appliedCoupon == nil
    }

    public var isApplied: Bool { state.appliedCoupon != nil }

    // MARK: - Actions

    /// Apply the current `codeInput`. Transitions through `.loading` → `.applied` or `.error`.
    public func apply() async {
        let trimmed = codeInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            state = .error("Please enter a coupon code.")
            return
        }

        state = .loading
        let request = CouponApplyRequest(code: trimmed, cartId: cartId())

        do {
            let response = try await api.post(
                "/coupons/apply",
                body: request,
                as: CouponApplyResponse.self
            )
            state = .applied(response.coupon, discountCents: response.discountCents)
        } catch let appError as AppError {
            state = .error(appError.errorDescription ?? appError.localizedDescription)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    /// Remove the currently applied coupon and reset to idle.
    public func remove() {
        codeInput = ""
        state = .idle
    }
}
