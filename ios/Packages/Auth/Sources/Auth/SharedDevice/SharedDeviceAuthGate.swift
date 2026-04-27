#if canImport(UIKit)
import SwiftUI
import LocalAuthentication
import DesignSystem
import Networking

// MARK: - §2.13 Shared-device enable/disable: requires device passcode + management PIN

/// Guards the enable/disable of shared-device mode behind two factors:
/// 1. Device passcode (system biometric or passcode via `LAContext`).
/// 2. Management PIN entered inline.
///
/// This ensures that a staff member cannot accidentally (or maliciously)
/// toggle shared-device mode without manager-level credentials.
///
/// Usage — replace the direct `SharedDeviceManager.enable/disable()` call
/// with this view's `onAuthorized` callback:
/// ```swift
/// SharedDeviceAuthGate(action: .enable) { authorised in
///     if authorised { await manager.enable() }
/// }
/// ```
public struct SharedDeviceAuthGate: View {

    public enum Action { case enable, disable }

    public let action: Action
    public let onAuthorized: (Bool) async -> Void

    @State private var managementPin: String = ""
    @State private var step: GateStep = .devicePasscode
    @State private var errorMessage: String? = nil
    @State private var isVerifying = false

    private let api: APIClient

    public init(action: Action, api: APIClient, onAuthorized: @escaping (Bool) async -> Void) {
        self.action = action
        self.api = api
        self.onAuthorized = onAuthorized
    }

    public var body: some View {
        VStack(spacing: BrandSpacing.xl) {
            headerView
            stepContent
            if let err = errorMessage {
                Text(err)
                    .font(.brandLabelSmall())
                    .foregroundStyle(Color.bizarreError)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(BrandSpacing.xxxl)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .task {
            if step == .devicePasscode { await promptDevicePasscode() }
        }
    }

    // MARK: - Sub-views

    private var headerView: some View {
        VStack(spacing: BrandSpacing.sm) {
            Image(systemName: "lock.shield")
                .font(.system(size: 40))
                .foregroundStyle(Color.bizarreOrange)
                .accessibilityHidden(true)

            Text(action == .enable ? "Enable Shared-Device Mode" : "Disable Shared-Device Mode")
                .font(.brandTitleLarge())
                .foregroundStyle(Color.bizarreOnSurface)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .devicePasscode:
            Text("Verifying device passcode…")
                .font(.brandBodySmall())
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityLabel("Verifying device passcode")

        case .managementPin:
            VStack(spacing: BrandSpacing.md) {
                Text("Enter the management PIN to continue.")
                    .font(.brandBodySmall())
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)

                SecureField("Management PIN", text: $managementPin)
                    .keyboardType(.numberPad)
                    .onChange(of: managementPin) { _, new in
                        managementPin = String(new.filter(\.isNumber).prefix(6))
                    }
                    .padding(.horizontal, BrandSpacing.md)
                    .padding(.vertical, BrandSpacing.base)
                    .frame(minHeight: 52)
                    .background(Color.bizarreSurface2.opacity(0.7),
                                in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.bizarreOutline.opacity(0.6), lineWidth: 0.5)
                    )
                    .privacySensitive()
                    .accessibilityLabel("Management PIN")

                Button {
                    Task { await verifyManagementPin() }
                } label: {
                    HStack {
                        if isVerifying { ProgressView().tint(Color.bizarreOnOrange) }
                        Text("Confirm")
                            .font(.brandTitleMedium().bold())
                    }
                }
                .buttonStyle(.brandGlassProminent)
                .tint(Color.bizarreOrange)
                .foregroundStyle(Color.bizarreOnOrange)
                .disabled(managementPin.count < 4 || isVerifying)
                .accessibilityIdentifier("sharedDeviceGate.confirm")
            }

        case .denied:
            Text("Authorization failed. Shared-device mode was not changed.")
                .font(.brandBodySmall())
                .foregroundStyle(Color.bizarreError)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Actions

    private func promptDevicePasscode() async {
        let ctx = LAContext()
        let reason = action == .enable
            ? "Authenticate to enable shared-device mode."
            : "Authenticate to disable shared-device mode."
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            step = .managementPin
            return
        }
        do {
            let ok = try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            step = ok ? .managementPin : .denied
            if !ok {
                errorMessage = "Device passcode verification failed."
                await onAuthorized(false)
            }
        } catch {
            step = .managementPin  // Biometrics unavailable — fall through to PIN
        }
    }

    private func verifyManagementPin() async {
        isVerifying = true
        errorMessage = nil
        do {
            try await api.verifyManagementPin(pin: managementPin)
            await onAuthorized(true)
        } catch {
            errorMessage = "Incorrect management PIN. Try again."
            managementPin = ""
        }
        isVerifying = false
    }
}

// MARK: - GateStep

private enum GateStep {
    case devicePasscode
    case managementPin
    case denied
}

// MARK: - APIClient extension

public extension APIClient {
    /// POST `/api/v1/auth/verify-management-pin`
    ///
    /// Verifies that the caller has management-level PIN authority.
    /// Used to gate sensitive operations like toggling shared-device mode.
    func verifyManagementPin(pin: String) async throws {
        struct Body: Encodable, Sendable { let pin: String }
        struct Empty: Decodable, Sendable {}
        _ = try await post(
            "/api/v1/auth/verify-management-pin",
            body: Body(pin: pin),
            as: Empty.self
        )
    }
}

#endif
