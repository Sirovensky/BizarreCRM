import SwiftUI
import DesignSystem

// MARK: - ManagerPinSheet

/// Minimal 4-digit PIN entry sheet for exiting kiosk mode.
/// If Pos package is imported and has a shared ManagerPinSheet, prefer that.
public struct ManagerPinSheet: View {
    let onSuccess: () -> Void
    let onCancel: () -> Void

    // In production, this PIN should come from secure config / server.
    // MVP: hardcoded 4-digit check via environment / default 1234.
    // TODO: Wire to tenant manager PIN from server settings.
    private let managerPin: String

    @State private var enteredDigits: [Int] = []
    @State private var shakeOffset: CGFloat = 0
    @State private var showError = false

    public init(
        managerPin: String = "1234",
        onSuccess: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.managerPin = managerPin
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

                if showError {
                    Text("Incorrect PIN. Try again.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                // Number pad
                numberPad
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

    // MARK: - Number pad

    private var numberPad: some View {
        let rows: [[Int?]] = [
            [1, 2, 3],
            [4, 5, 6],
            [7, 8, 9],
            [nil, 0, -1]  // nil = blank, -1 = delete
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
        showError = false
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
        if entered == managerPin {
            onSuccess()
        } else {
            showError = true
            enteredDigits = []
            withAnimation(.default) {
                shakeOffset = 8
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                withAnimation(.default) { shakeOffset = -8 }
                try? await Task.sleep(for: .milliseconds(100))
                withAnimation(.default) { shakeOffset = 0 }
            }
        }
    }
}
