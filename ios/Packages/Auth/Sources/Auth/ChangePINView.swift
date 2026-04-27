#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Networking
import Persistence
import Core

// MARK: - ChangePINView
//
// §2.5 — Settings → Security → Change PIN.
// Verifies current PIN locally, then calls POST /api/v1/auth/change-pin
// with { currentPin, newPin } and re-enrols the local hash.

@Observable
@MainActor
private final class ChangePINViewModel {
    var currentPin: String = ""
    var newPin: String = ""
    var confirmPin: String = ""
    var isSubmitting: Bool = false
    var errorMessage: String? = nil
    var successMessage: String? = nil

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    var canSubmit: Bool {
        currentPin.count >= 4 &&
        newPin.count >= 4 && newPin.count <= 6 &&
        newPin == confirmPin &&
        !isSubmitting
    }

    func submit() async {
        errorMessage = nil
        successMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }

        // Validate locally first to give fast feedback
        let localResult = PINStore.shared.verify(pin: currentPin)
        switch localResult {
        case .wrong:
            errorMessage = "Current PIN is incorrect."
            return
        case .lockedOut(let until):
            let remaining = Int(until.timeIntervalSinceNow.rounded(.up))
            errorMessage = "Too many wrong tries. Wait \(remaining)s."
            return
        case .revoked:
            errorMessage = "PIN is revoked. Sign in again to set a new one."
            return
        case .ok:
            break
        }

        guard newPin == confirmPin else {
            errorMessage = "New PINs don't match."
            return
        }
        guard newPin.count >= 4, newPin.count <= 6 else {
            errorMessage = "PIN must be 4–6 digits."
            return
        }

        // Server mirror
        do {
            _ = try await api.changePin(ChangePinBody(currentPin: currentPin, newPin: newPin))
        } catch APITransportError.httpStatus(let code, _) where code == 401 {
            errorMessage = "Current PIN rejected by server."
            return
        } catch {
            // Non-fatal: server may not support change-pin; fall through to local re-enrol
            AppLog.auth.warning("change-pin server call failed (non-fatal): \(error.localizedDescription, privacy: .public)")
        }

        // Re-enrol local hash
        do {
            try PINStore.shared.enrol(pin: newPin)
            successMessage = "PIN changed."
            currentPin = ""; newPin = ""; confirmPin = ""
        } catch {
            errorMessage = "Failed to save new PIN: \(error.localizedDescription)"
        }
    }
}

public struct ChangePINView: View {
    @State private var vm: ChangePINViewModel
    @Environment(\.dismiss) private var dismiss

    public init(api: APIClient) {
        _vm = State(wrappedValue: ChangePINViewModel(api: api))
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Current PIN") {
                    SecureField("Current PIN", text: $vm.currentPin)
                        .keyboardType(.numberPad)
                        .textContentType(.password)
                        .onChange(of: vm.currentPin) { _, v in
                            vm.currentPin = String(v.filter(\.isNumber).prefix(6))
                        }
                        .accessibilityIdentifier("changePIN.current")
                }

                Section("New PIN") {
                    SecureField("New PIN (4–6 digits)", text: $vm.newPin)
                        .keyboardType(.numberPad)
                        .onChange(of: vm.newPin) { _, v in
                            vm.newPin = String(v.filter(\.isNumber).prefix(6))
                        }
                        .accessibilityIdentifier("changePIN.new")

                    SecureField("Confirm new PIN", text: $vm.confirmPin)
                        .keyboardType(.numberPad)
                        .onChange(of: vm.confirmPin) { _, v in
                            vm.confirmPin = String(v.filter(\.isNumber).prefix(6))
                        }
                        .accessibilityIdentifier("changePIN.confirm")
                }

                if let err = vm.errorMessage {
                    Section {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.bizarreError)
                    }
                }
                if let ok = vm.successMessage {
                    Section {
                        Label(ok, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.bizarreSuccess)
                    }
                }

                Section {
                    Button {
                        Task { await vm.submit() }
                    } label: {
                        HStack {
                            Spacer()
                            if vm.isSubmitting { ProgressView() }
                            else { Text("Change PIN").fontWeight(.semibold) }
                            Spacer()
                        }
                    }
                    .disabled(!vm.canSubmit)
                    .accessibilityIdentifier("changePIN.submit")
                }
            }
            .navigationTitle("Change PIN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

#endif
