import Foundation
import Observation
import Networking

/// §38 — View-model for `LoyaltyBalanceView`.
///
/// State machine: loading → loaded | failed | comingSoon.
/// `passData` is populated only after a successful `downloadPass` call.
@MainActor
@Observable
public final class LoyaltyBalanceViewModel {

    // MARK: - State

    public enum State: Equatable, Sendable {
        case loading
        case loaded
        case failed(String)
        case comingSoon
    }

    public private(set) var state: State = .loading
    public private(set) var balance: LoyaltyBalance?
    public private(set) var passData: Data?

    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    // MARK: - Load balance

    /// Fetch the loyalty balance for `customerId` and update `state`.
    ///
    /// 501 → `.comingSoon` so the UI shows a placeholder rather than
    /// an error. Other failures surface as `.failed`.
    public func loadBalance(customerId: Int64) async {
        state = .loading
        balance = nil
        do {
            let result = try await api.getLoyaltyBalance(customerId: customerId)
            balance = result
            state = .loaded
        } catch let transport as APITransportError {
            state = comingSoonOrFailed(transport)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Download pass

    /// Download the raw `.pkpass` data for `customerId`.
    ///
    /// 501 → `.comingSoon`. Other failures surface as `.failed`.
    /// On success, populates `passData` for the presenter to consume.
    public func downloadPass(customerId: Int64) async {
        do {
            let data = try await api.fetchLoyaltyPass(customerId: customerId)
            passData = data
        } catch let transport as APITransportError {
            // Demote to coming-soon if the server hasn't shipped the endpoint.
            state = comingSoonOrFailed(transport)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Helpers

    /// Translates a transport error into the appropriate `State`.
    ///
    /// 404 and 501 → `.comingSoon`. Everything else → `.failed`.
    private func comingSoonOrFailed(_ error: APITransportError) -> State {
        if case .httpStatus(let code, _) = error, code == 404 || code == 501 {
            return .comingSoon
        }
        return .failed(error.localizedDescription)
    }
}
