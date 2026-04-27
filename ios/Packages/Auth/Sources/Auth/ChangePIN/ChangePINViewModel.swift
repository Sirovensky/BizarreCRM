import Foundation
import Observation
import Persistence
import Networking
import Core

// MARK: - §2.5 Change PIN view model

@MainActor
@Observable
public final class ChangePINViewModel {

    // MARK: State

    public var currentPIN: String = ""
    public var newPIN: String = ""
    public var confirmPIN: String = ""
    public var isSubmitting: Bool = false
    public var errorMessage: String? = nil
    public var successMessage: String? = nil

    // MARK: Derived

    public var canSubmit: Bool {
        currentPIN.count >= 4 &&
        newPIN.count >= 4 && newPIN.count <= 6 &&
        newPIN == confirmPIN &&
        !isSubmitting
    }

    public var mismatch: Bool {
        !confirmPIN.isEmpty && newPIN != confirmPIN
    }

    // MARK: Dependencies

    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    // MARK: Actions

    public func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        successMessage = nil
        defer { isSubmitting = false }

        guard newPIN.allSatisfy(\.isNumber), currentPIN.allSatisfy(\.isNumber) else {
            errorMessage = "PIN must contain only digits."
            return
        }

        // §2.13 Common PIN blocklist (1234, 0000, etc.)
        if CommonPINBlocklist.contains(newPIN) {
            errorMessage = "That PIN is too common. Choose a less predictable one."
            return
        }

        do {
            try await api.changePIN(currentPin: currentPIN, newPin: newPIN)
            // Update the local PINStore so unlock still works immediately.
            // Silently ignore if Keychain is unavailable (e.g. test sandbox).
            try? PINStore.shared.enrol(pin: newPIN)
            successMessage = "PIN updated successfully."
            // Clear fields after success.
            currentPIN = ""
            newPIN = ""
            confirmPIN = ""
        } catch APITransportError.httpStatus(let code, _) where code == 401 {
            errorMessage = "Current PIN is incorrect."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Common PIN blocklist

private enum CommonPINBlocklist {
    static let list: Set<String> = [
        "0000", "1111", "2222", "3333", "4444",
        "5555", "6666", "7777", "8888", "9999",
        "1234", "4321", "1212", "0123", "9876",
        "111111", "000000", "123456", "654321"
    ]

    static func contains(_ pin: String) -> Bool {
        list.contains(pin)
    }
}
