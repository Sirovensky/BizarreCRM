#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// MARK: - §2.5 Switch User Settings Row

/// Settings → Security → "Switch user" row (shared-device mode only).
///
/// Shows a PIN pad sheet to authenticate a different staff member on the
/// same device without full sign-out. Only visible when `SharedDeviceManager`
/// reports shared-device mode is active.
///
/// Also exposed via long-press on the avatar in the toolbar — callers embed
/// this view or call `SwitchUserCoordinator.presentIfNeeded()`.
public struct SwitchUserSettingsRow: View {

    @State private var showPinPad: Bool = false
    @State private var switchResult: SwitchResultDisplay? = nil
    @State private var isSharedDevice: Bool = false

    private let service: PinSwitchService
    private let onSuccess: @MainActor (SwitchedUser) -> Void

    public init(
        service: PinSwitchService,
        onSuccess: @escaping @MainActor (SwitchedUser) -> Void
    ) {
        self.service = service
        self.onSuccess = onSuccess
    }

    public var body: some View {
        Group {
            if isSharedDevice {
                rowButton
            }
        }
        .task {
            isSharedDevice = await SharedDeviceManager.shared.isSharedDevice
        }
        .sheet(isPresented: $showPinPad) {
            SwitchUserPinSheet(service: service) { result in
                handleResult(result)
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .alert(switchResult?.title ?? "", isPresented: Binding(
            get: { switchResult != nil },
            set: { if !$0 { switchResult = nil } }
        )) {
            Button("OK", role: .cancel) { switchResult = nil }
        } message: {
            if let msg = switchResult?.message {
                Text(msg)
            }
        }
    }

    // MARK: - Row

    private var rowButton: some View {
        Button {
            showPinPad = true
        } label: {
            Label("Switch user", systemImage: "person.2.circle")
                .font(.brandBodyLarge())
                .foregroundStyle(Color.bizarreOnSurface)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Switch user")
        .accessibilityHint("Authenticate as a different staff member using your PIN.")
    }

    // MARK: - Result handler

    private func handleResult(_ result: SwitchResult) {
        switch result {
        case .success(_, let user):
            showPinPad = false
            onSuccess(user)
        case .wrongPin:
            switchResult = SwitchResultDisplay(
                title: "Incorrect PIN",
                message: "Try again or ask your manager."
            )
        case .locked(let until):
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            let rel = formatter.localizedString(for: until, relativeTo: Date())
            switchResult = SwitchResultDisplay(
                title: "Too many attempts",
                message: "Try again \(rel)."
            )
        case .revoked:
            switchResult = SwitchResultDisplay(
                title: "Account locked",
                message: "Too many failed attempts. Sign in with your password."
            )
        case .networkError:
            switchResult = SwitchResultDisplay(
                title: "Network error",
                message: "Couldn't reach the server. Check your connection and try again."
            )
        }
    }
}

// MARK: - SwitchUserPinSheet

/// Full-screen (iPhone) / sheet (iPad) PIN pad for switching users.
private struct SwitchUserPinSheet: View {
    let service: PinSwitchService
    let onResult: @MainActor (SwitchResult) -> Void

    var body: some View {
        NavigationStack {
            PinPadView(
                title: "Switch user",
                subtitle: "Enter your PIN to continue"
            ) { pin in
                let result = await service.attempt(pin: pin)
                await MainActor.run { onResult(result) }
            }
            .navigationTitle("Switch user")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onResult(.wrongPin) }
                        .accessibilityLabel("Cancel user switch")
                }
            }
        }
    }
}

// MARK: - SwitchResultDisplay helper

private struct SwitchResultDisplay {
    let title: String
    let message: String
}

#endif
