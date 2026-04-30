import SwiftUI
import Observation
import Core
import DesignSystem
import Persistence

// MARK: - §19.2 6-digit PIN for quick re-auth (locally enforced)
//
// Uses `PINStore.shared` from Persistence (Keychain-backed, SHA-256 hashed,
// with escalating lockout). Settings wraps enrollment into a guided sheet with
// a dot-entry field. The AuthPackage also shows PINSetup at first login; this
// Settings page lets users change or remove the PIN post-enrollment.

// MARK: - ViewModel

@MainActor
@Observable
public final class PINSetupViewModel {
    public enum Mode { case set, change }

    public var currentEntry: String = ""  // current PIN (change mode)
    public var firstEntry:   String = ""  // new PIN (first entry)
    public var secondEntry:  String = ""  // new PIN (confirmation)
    public var errorMessage: String?
    public var isSuccess:    Bool = false
    public let mode: Mode

    public init(mode: Mode = .set) {
        self.mode = mode
    }

    /// Validate inputs and enrol/update the PIN.
    public func submit() {
        errorMessage = nil

        switch mode {
        case .set:
            guard firstEntry.count >= 4, firstEntry.count <= 6 else {
                errorMessage = "PIN must be 4–6 digits."; return
            }
            guard firstEntry == secondEntry else {
                errorMessage = "PINs don't match. Try again."
                secondEntry = ""; return
            }
            do {
                try PINStore.shared.enrol(pin: firstEntry)
                isSuccess = true
            } catch {
                errorMessage = error.localizedDescription
            }

        case .change:
            // Verify existing PIN first.
            let verifyResult = PINStore.shared.verify(pin: currentEntry)
            guard case .ok = verifyResult else {
                errorMessage = "Current PIN is incorrect."; currentEntry = ""; return
            }
            guard firstEntry.count >= 4, firstEntry.count <= 6 else {
                errorMessage = "New PIN must be 4–6 digits."; return
            }
            guard firstEntry == secondEntry else {
                errorMessage = "New PINs don't match."; secondEntry = ""; return
            }
            do {
                try PINStore.shared.enrol(pin: firstEntry)
                isSuccess = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Remove the enrolled PIN after verifying the current one.
    public func removePIN() {
        errorMessage = nil
        let verifyResult = PINStore.shared.verify(pin: currentEntry)
        guard case .ok = verifyResult else {
            errorMessage = "Enter your current PIN to confirm removal."; currentEntry = ""; return
        }
        PINStore.shared.reset()
        isSuccess = true
    }
}

// MARK: - 6-dot PIN entry field

/// Displays filled / empty circles to represent each digit typed.
/// Backed by a hidden numeric `TextField`; tapping the dot row focuses it.
struct PINDotField: View {
    @Binding var text: String
    var maxLength: Int = 6
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            // Hidden text capture layer
            TextField("", text: $text)
                .keyboardType(.numberPad)
                .focused($isFocused)
                .opacity(0)
                .frame(width: 1, height: 1)
                .onChange(of: text) { _, new in
                    let filtered = String(new.filter(\.isNumber).prefix(maxLength))
                    if filtered != new { text = filtered }
                }

            // Visual indicators
            HStack(spacing: 16) {
                ForEach(0..<maxLength, id: \.self) { idx in
                    Circle()
                        .fill(idx < text.count
                              ? Color.bizarreOrange
                              : Color.bizarreOnSurfaceMuted.opacity(0.2))
                        .frame(width: 16, height: 16)
                        .overlay(
                            Circle().strokeBorder(
                                idx < text.count
                                    ? Color.bizarreOrange
                                    : Color.bizarreOutline.opacity(0.45),
                                lineWidth: 1
                            )
                        )
                        .animation(.easeInOut(duration: 0.12), value: text.count)
                }
            }
            .onTapGesture { isFocused = true }
        }
        .onAppear { isFocused = true }
        .accessibilityLabel("PIN entry field, \(text.count) of \(maxLength) digits entered")
    }
}

// MARK: - PINSetupSheet

/// Modal sheet for enrolling or changing the app's quick-access PIN.
/// Presented from Settings → Security.
public struct PINSetupSheet: View {
    @State private var vm: PINSetupViewModel
    let onComplete: () -> Void

    public init(mode: PINSetupViewModel.Mode = .set, onComplete: @escaping () -> Void) {
        _vm = State(wrappedValue: PINSetupViewModel(mode: mode))
        self.onComplete = onComplete
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: BrandSpacing.xl) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 48, weight: .regular))
                            .foregroundStyle(.bizarreOrange)
                            .padding(.top, BrandSpacing.xl)
                            .accessibilityHidden(true)

                        Text(title)
                            .font(.brandTitleLarge())
                            .foregroundStyle(.bizarreOnSurface)
                            .multilineTextAlignment(.center)

                        Text(subtitle)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, BrandSpacing.lg)

                        formRows

                        if let error = vm.errorMessage {
                            Text(error)
                                .font(.brandLabelLarge())
                                .foregroundStyle(.bizarreError)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, BrandSpacing.lg)
                        }

                        Button(action: { vm.submit() }) {
                            Text(vm.mode == .change ? "Update PIN" : "Set PIN")
                                .font(.brandBodyLarge().weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, BrandSpacing.md)
                                .background(Color.bizarreOrange, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.horizontal, BrandSpacing.lg)
                        .accessibilityIdentifier("pin.confirmButton")

                        Spacer(minLength: BrandSpacing.xl)
                    }
                }
            }
            .navigationTitle(vm.mode == .change ? "Change PIN" : "Set up PIN")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onComplete)
                        .accessibilityIdentifier("pin.cancelButton")
                }
            }
            .onChange(of: vm.isSuccess) { _, success in
                if success { onComplete() }
            }
        }
    }

    @ViewBuilder
    private var formRows: some View {
        VStack(spacing: BrandSpacing.lg) {
            if vm.mode == .change {
                pinRow(label: "Current PIN", binding: $vm.currentEntry)
                Divider()
            }
            pinRow(label: vm.mode == .change ? "New PIN" : "Enter PIN", binding: $vm.firstEntry)
            pinRow(label: "Confirm PIN", binding: $vm.secondEntry)
        }
        .padding(.horizontal, BrandSpacing.lg)
    }

    private func pinRow(label: String, binding: Binding<String>) -> some View {
        VStack(spacing: BrandSpacing.sm) {
            Text(label)
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            PINDotField(text: binding, maxLength: 6)
        }
    }

    private var title: String {
        vm.mode == .change ? "Change your PIN" : "Set a Quick-access PIN"
    }

    private var subtitle: String {
        vm.mode == .change
            ? "Enter your current PIN, then choose a new one."
            : "A 4–6 digit PIN lets you unlock the app quickly without biometrics."
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Set PIN") {
    PINSetupSheet(mode: .set) {}
}
#Preview("Change PIN") {
    PINSetupSheet(mode: .change) {}
}
#endif
