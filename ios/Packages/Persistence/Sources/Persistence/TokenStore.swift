import Foundation
import Observation
import Core

/// Lazy token cache — Keychain is only read the first time a caller asks for
/// a token. Avoids a synchronous Keychain hit on the main actor during app
/// launch, which was measurable on cold start.
@MainActor
@Observable
public final class TokenStore {
    public static let shared = TokenStore()

    @ObservationIgnored private var didLoad = false
    private var _access: String?
    private var _refresh: String?

    public var accessToken: String? {
        if !didLoad { load() }
        return _access
    }

    public var refreshToken: String? {
        if !didLoad { load() }
        return _refresh
    }

    public var hasValidSession: Bool { accessToken != nil }

    private init() {}

    private func load() {
        _access = KeychainStore.shared.get(.accessToken)
        _refresh = KeychainStore.shared.get(.refreshToken)
        didLoad = true
    }

    public func save(access: String, refresh: String) {
        // BUGHUNT-2026-05-17: previously the two Keychain writes happened
        // sequentially with no rollback — if the access-token write succeeded
        // but the refresh-token write threw, the Keychain held a NEW access
        // token paired with an OLD or missing refresh, while the in-memory
        // cache held neither (because the do-block aborted before updating
        // _access/_refresh). The next read then loaded the mismatched pair
        // from Keychain and the app silently authenticated against a server
        // expecting the refresh pair to match. Roll back the access-token
        // write if the refresh-token write fails so the pair stays atomic.
        do {
            try KeychainStore.shared.set(access, for: .accessToken)
        } catch {
            AppLog.auth.error("Failed to persist access token: \(error.localizedDescription)")
            return
        }
        do {
            try KeychainStore.shared.set(refresh, for: .refreshToken)
        } catch {
            AppLog.auth.error("Failed to persist refresh token, rolling back access: \(error.localizedDescription)")
            // Best-effort rollback. If this throws too, the inconsistency is
            // already there — but the in-memory state stays nil so the next
            // read picks up the Keychain state and the auth refresh path
            // will detect the mismatch via a 401 response.
            try? KeychainStore.shared.remove(.accessToken)
            _access = nil
            _refresh = nil
            didLoad = true
            return
        }
        _access = access
        _refresh = refresh
        didLoad = true
    }

    public func clear() {
        try? KeychainStore.shared.remove(.accessToken)
        try? KeychainStore.shared.remove(.refreshToken)
        _access = nil
        _refresh = nil
        didLoad = true
    }
}
