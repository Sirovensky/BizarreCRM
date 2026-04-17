import Foundation
import Observation
import Core

@MainActor
@Observable
public final class TokenStore {
    public static let shared = TokenStore()

    public private(set) var accessToken: String?
    public private(set) var refreshToken: String?

    public var hasValidSession: Bool { accessToken != nil }

    private init() {
        self.accessToken = KeychainStore.shared.get(.accessToken)
        self.refreshToken = KeychainStore.shared.get(.refreshToken)
    }

    public func save(access: String, refresh: String) {
        do {
            try KeychainStore.shared.set(access, for: .accessToken)
            try KeychainStore.shared.set(refresh, for: .refreshToken)
            self.accessToken = access
            self.refreshToken = refresh
        } catch {
            AppLog.auth.error("Failed to persist tokens: \(error.localizedDescription)")
        }
    }

    public func clear() {
        try? KeychainStore.shared.remove(.accessToken)
        try? KeychainStore.shared.remove(.refreshToken)
        self.accessToken = nil
        self.refreshToken = nil
    }
}
