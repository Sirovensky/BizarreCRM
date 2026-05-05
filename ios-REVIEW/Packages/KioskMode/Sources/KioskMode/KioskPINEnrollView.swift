import SwiftUI
import DesignSystem

// MARK: - KioskPINEnrollView

/// §55.3 PIN enrollment sheet shown when a manager first enables kiosk mode
/// and no PIN is stored in Keychain.
///
/// Two-phase: enter a 4-digit PIN, then confirm it. On success calls
/// `onEnrolled` so the caller can proceed to activate kiosk mode.
public struct KioskPINEnrollView: View {
    let pinStorage: any KioskPINStorage
    let onEnrolled: () -> Void
    let onCancel: () -> Void

    private enum Phase {
        case enter, confirm
    }

    @State private var phase: Phase = .enter
    @State private var firstDigits: [Int] = []
    @State private var confirmDigits: [Int] = []
    @State private var shakeOffset: CGFloat = 0
    @State private var mismatchError = false
    @State private var enrollError: String?

    public init(
        pinStorage: any KioskPINStorage,
        onEnrolled: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.pinStorage = pinStorage
        self.onEnrolled = onEnrolled
        self.onCancel = onCancel
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: DesignTokens.Spacing.xxxl) {
                VStack(spacing: DesignTokens.Spacing.sm) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)

                    Text(phase == .enter ? "Set Manager PIN" : "Confirm PIN")
                        .font(.title3.bold())

                    Text(phase == .enter
                         ? "Choose a 4-digit PIN to protect kiosk exit."
                         : "Re-enter the same 4 digits to confirm.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                // PIN dot row
                pinDotRow

                // Error label
                if mismatchError {
                    Text("PINs don't match. Start again.")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityLabel("Error: PINs don't match. Start again.")
                }
                if let err = enrollError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                // Number pad
                numberPad
            }
            .padding(DesignTokens.Spacing.xl)
            .navigationTitle("Kiosk PIN Setup")
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

    // MARK: - PIN dot display

    private var activeDigits: [Int] {
        phase == .enter ? firstDigits : confirmDigits
    }

    private var pinDotRow: some View {
        HStack(spacing: DesignTokens.Spacing.xl) {
            ForEach(0..<4, id: \.self) { idx in
                Circle()
                    .fill(idx < activeDigits.count ? Color.orange : Color.secondary.opacity(0.3))
                    .frame(width: 16, height: 16)
            }
        }
        .offset(x: shakeOffset)
        .accessibilityLabel("PIN entry: \(activeDigits.count) of 4 digits entered")
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
        mismatchError = false
        enrollError = nil

        if key == -1 {
            if phase == .enter {
                if !firstDigits.isEmpty { firstDigits.removeLast() }
            } else {
                if !confirmDigits.isEmpty {
                    confirmDigits.removeLast()
                } else {
                    // Back past empty confirm → return to entry phase
                    phase = .enter
                    firstDigits = []
                }
            }
            return
        }

        if phase == .enter {
            guard firstDigits.count < 4 else { return }
            firstDigits.append(key)
            if firstDigits.count == 4 {
                phase = .confirm
            }
        } else {
            guard confirmDigits.count < 4 else { return }
            confirmDigits.append(key)
            if confirmDigits.count == 4 {
                commitEnrollment()
            }
        }
    }

    private func commitEnrollment() {
        let first = firstDigits.map { String($0) }.joined()
        let confirm = confirmDigits.map { String($0) }.joined()
        guard first == confirm else {
            mismatchError = true
            confirmDigits = []
            firstDigits = []
            phase = .enter
            shake()
            return
        }
        do {
            try pinStorage.enrol(pin: first)
            onEnrolled()
        } catch {
            enrollError = error.localizedDescription
            confirmDigits = []
            firstDigits = []
            phase = .enter
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
