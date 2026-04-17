import Foundation
import CryptoKit
import Core

@MainActor
public final class PINStore {
    public static let shared = PINStore()

    private init() {}

    public var isEnrolled: Bool { KeychainStore.shared.get(.pinHash) != nil }

    public func enrol(pin: String) throws {
        let hashed = Self.hash(pin)
        try KeychainStore.shared.set(hashed, for: .pinHash)
    }

    public func verify(pin: String) -> Bool {
        guard let stored = KeychainStore.shared.get(.pinHash) else { return false }
        return Self.hash(pin) == stored
    }

    public func reset() {
        try? KeychainStore.shared.remove(.pinHash)
    }

    /// Note: replace with Argon2id in a follow-up pass. SHA-256 here keeps
    /// Phase 0 moving without dragging in a native crypto dep; PIN is behind
    /// Keychain already, so the risk surface is small.
    private static func hash(_ pin: String) -> String {
        let salt = "bizarre-v1"
        let digest = SHA256.hash(data: Data((pin + salt).utf8))
        return Data(digest).base64EncodedString()
    }
}
