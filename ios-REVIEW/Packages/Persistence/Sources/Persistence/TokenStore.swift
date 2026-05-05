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
        do {
            try KeychainStore.shared.set(access, for: .accessToken)
            try KeychainStore.shared.set(refresh, for: .refreshToken)
            _access = access
            _refresh = refresh
            didLoad = true
        } catch {
            AppLog.auth.error("Failed to persist tokens: \(error.localizedDescription)")
        }
    }

    public func clear() {
        try? KeychainStore.shared.remove(.accessToken)
        try? KeychainStore.shared.remove(.refreshToken)
        _access = nil
        _refresh = nil
        didLoad = true
    }
}
