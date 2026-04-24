import SwiftUI
import DesignSystem

// MARK: - ManagerPinSheet

/// §55.2 Manager PIN sheet for exiting kiosk mode.
/// Delegates storage and lockout logic to `KioskPINStorage`.
/// Production code passes `PINStoreKioskAdapter`; tests pass
/// `InMemoryKioskPINStorage`.
public struct ManagerPinSheet: View {
    let pinStorage: any KioskPINStorage
    let onSuccess: () -> Void
    let onCancel: () -> Void

    @State private var enteredDigits: [Int] = []
    @State private var shakeOffset: CGFloat = 0
    @State private var verifyResult: KioskPINVerifyResult?

    public init(
        pinStorage: any KioskPINStorage,
        onSuccess: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.pinStorage = pinStorage
        self.onSuccess = onSuccess
        self.onCancel = onCancel
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: DesignTokens.Spacing.xxxl) {
                Text("Manager PIN Required")
                    .font(.title3.bold())

                // PIN dot display
                HStack(spacing: DesignTokens.Spacing.xl) {
                    ForEach(0..<4, id: \.self) { idx in
                        Circle()
                            .fill(idx < enteredDigits.count ? Color.orange : Color.secondary.opacity(0.3))
                            .frame(width: 16, height: 16)
                    }
                }
                .offset(x: shakeOffset)
                .accessibilityLabel("PIN entry: \(enteredDigits.count) of 4 digits entered")

                statusLabel

                // Number pad — disabled during lockout or revocation
                numberPad
                    .disabled(isPadDisabled)
            }
            .padding(DesignTokens.Spacing.xl)
            .navigationTitle("Exit Kiosk")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium])
        #endif
    }

    // MARK: - Status

    @ViewBuilder
    private var statusLabel: some View {
        switch verifyResult {
        case .wrong(let remaining):
            Text(remaining == 0
                 ? "Incorrect PIN."
                 : "Incorrect PIN. \(remaining) \(remaining == 1 ? "attempt" : "attempts") left before lockout.")
                .font(.caption)
                .foregroundStyle(.red)
                .accessibilityLabel("Incorrect PIN. \(remaining) attempts remaining.")

        case .lockedOut(let until):
            Text("Too many attempts. Try again after \(until, style: .time).")
                .font(.caption)
                .foregroundStyle(.red)
                .accessibilityLabel("PIN entry locked until \(until, style: .time).")

        case .revoked:
            Text("PIN revoked after too many failures. Contact your manager.")
                .font(.caption)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .accessibilityLabel("PIN entry revoked. Contact your manager.")

        case .ok, .none:
            EmptyView()
        }
    }

    private var isPadDisabled: Bool {
        switch verifyResult {
        case .lockedOut, .revoked: return true
        default: return false
        }
    }

    // MARK: - Number pad

    private var numberPad: some View {
        let rows: [[Int?]] = [
            [1, 2, 3],
            [4, 5, 6],
            [7, 8, 9],
            [nil, 0, -1]
        ]
        return VStack(spacing: DesignTokens.Spacing.md) {
            ForEach(0..<rows.count, id: \.self) { r in
                HStack(spacing: DesignTokens.Spacing.md) {
                    ForEach(0..<rows[r].count, id: \.self) { c in
                        if let key = rows[r][c] {
                            padButton(key: key)
                        } else {
                            Color.clear.frame(width: 72, height: 56)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func padButton(key: Int) -> some View {
        Button {
            handleKey(key)
        } label: {
            Group {
                if key == -1 {
                    Image(systemName: "delete.left")
                        .font(.title3)
                } else {
                    Text("\(key)")
                        .font(.title2.monospacedDigit())
                }
            }
            .frame(width: 72, height: 56)
        }
        .buttonStyle(.borderless)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .accessibilityLabel(key == -1 ? "Delete" : "\(key)")
    }

    // MARK: - Input handling

    private func handleKey(_ key: Int) {
        verifyResult = nil
        if key == -1 {
            if !enteredDigits.isEmpty { enteredDigits.removeLast() }
            return
        }
        guard enteredDigits.count < 4 else { return }
        enteredDigits.append(key)
        if enteredDigits.count == 4 {
            validatePin()
        }
    }

    private func validatePin() {
        let entered = enteredDigits.map { String($0) }.joined()
        let result = pinStorage.verify(pin: entered)
        verifyResult = result
        switch result {
        case .ok:
            onSuccess()
        case .wrong, .lockedOut, .revoked:
            enteredDigits = []
            shake()
        }
    }

    private func shake() {
        Task { @MainActor in
            withAnimation(.default) { shakeOffset = 8 }
            try? await Task.sleep(for: .milliseconds(100))
            withAnimation(.default) { shakeOffset = -8 }
            try? await Task.sleep(for: .milliseconds(100))
            withAnimation(.default) { shakeOffset = 0 }
        }
    }
}
