import Foundation
import Persistence

// MARK: - KioskPINStorage

/// Minimal PIN-storage contract used by `ManagerPinSheet` and
/// `KioskPINEnrollView`. Production wires `PINStoreKioskAdapter`; tests inject
/// `InMemoryKioskPINStorage` to avoid real Keychain access.
@MainActor
public protocol KioskPINStorage: AnyObject {
    /// Whether a PIN is currently enrolled.
    var isEnrolled: Bool { get }

    /// Enrol (or replace) the stored PIN.
    func enrol(pin: String) throws

    /// Attempt to verify the PIN, applying escalating lockout on failure.
    func verify(pin: String) -> KioskPINVerifyResult

    /// Remove the stored PIN and reset failure counters.
    func reset()
}

// MARK: - KioskPINVerifyResult

public enum KioskPINVerifyResult: Equatable, Sendable {
    /// PIN matched; counter reset.
    case ok
    /// PIN wrong but retries remain.
    case wrong(remainingBeforeLockout: Int)
    /// Temporary lockout until `until`.
    case lockedOut(until: Date)
    /// Maximum failures reached — re-auth required.
    case revoked
}

// MARK: - PINStoreKioskAdapter

/// Bridges `Persistence.PINStore` to `KioskPINStorage`.
/// Production code uses this; tests use `InMemoryKioskPINStorage`.
@MainActor
public final class PINStoreKioskAdapter: KioskPINStorage {
    private let store: PINStore

    public init(store: PINStore = .shared) {
        self.store = store
    }

    public var isEnrolled: Bool {
        store.isEnrolled
    }

    public func enrol(pin: String) throws {
        try store.enrol(pin: pin)
    }

    public func verify(pin: String) -> KioskPINVerifyResult {
        switch store.verify(pin: pin) {
        case .ok:
            return .ok
        case .wrong(let remaining):
            return .wrong(remainingBeforeLockout: remaining)
        case .lockedOut(let until):
            return .lockedOut(until: until)
        case .revoked:
            return .revoked
        }
    }

    public func reset() {
        store.reset()
    }
}

// MARK: - InMemoryKioskPINStorage (tests only)

/// Thread-safe in-memory PIN storage for unit tests.
/// Deliberately minimal: no lockout escalation, just enrol + verify.
@MainActor
public final class InMemoryKioskPINStorage: KioskPINStorage {
    private var storedPIN: String?
    private var failCount: Int = 0

    public init(storedPIN: String? = nil) {
        self.storedPIN = storedPIN
    }

    public var isEnrolled: Bool { storedPIN != nil }

    public func enrol(pin: String) throws {
        guard !pin.isEmpty else { return }
        storedPIN = pin
        failCount = 0
    }

    public func verify(pin: String) -> KioskPINVerifyResult {
        guard let stored = storedPIN else { return .revoked }
        if pin == stored {
            failCount = 0
            return .ok
        }
        failCount += 1
        if failCount >= 10 {
            storedPIN = nil
            return .revoked
        }
        if failCount >= 5 {
            return .lockedOut(until: Date().addingTimeInterval(30))
        }
        return .wrong(remainingBeforeLockout: max(0, 5 - failCount))
    }

    public func reset() {
        storedPIN = nil
        failCount = 0
    }
}
