import SwiftUI
import Networking
import Core

// MARK: - §19.2 2FA — TOTP enrollment (QR scan + verification + backup codes)
//
// Flow:
//   1. POST /auth/totp/setup → {secret, qr_url, backup_codes[]}
//   2. User scans QR with Authenticator / 1Password / iCloud Keychain
//   3. User types the 6-digit code to confirm; POST /auth/totp/verify
//   4. Success → backup codes shown with copy/export options; call onEnrolled
//
// Self-service disable is blocked by policy (2026-04-23).
// Recovery via backup-code flow + super-admin force-disable only.

// MARK: - Model

/// Local response model mapped from `TOTPSetupWire` in SecuritySettingsEndpoints.
public struct TOTPSetupResponse: Sendable {
    public let secret: String
    public let qrURL: URL
    public let backupCodes: [String]
}

// MARK: - ViewModel

@MainActor @Observable
public final class TOTPEnrollmentViewModel {

    public enum Step {
        case loading
        case scanQR(TOTPSetupResponse)
        case verifying
        case showBackupCodes([String])
        case error(String)
    }

    public var step: Step = .loading
    public var codeInput: String = ""
    public var isConfirming: Bool = false
    public var verifyError: String?
    public var didCopyBackupCodes: Bool = false

    private let api: APIClient?

    public init(api: APIClient? = nil) {
        self.api = api
    }

    // MARK: - Lifecycle

    public func startSetup() async {
        step = .loading
        do {
            guard let api else { return }
            let wire = try await api.securityTotpSetup()
            guard let qrURL = URL(string: wire.qrURL) else {
                step = .error("Invalid QR URL from server")
                return
            }
            step = .scanQR(TOTPSetupResponse(secret: wire.secret, qrURL: qrURL, backupCodes: wire.backupCodes))
        } catch {
            step = .error(error.localizedDescription)
        }
    }

    public func confirmCode(secret: String, backupCodes: [String]) async {
        guard codeInput.count == 6 else {
            verifyError = "Enter the 6-digit code from your authenticator app."
            return
        }
        isConfirming = true
        verifyError = nil
        defer { isConfirming = false }
        do {
            try await api?.securityTotpVerify(secret: secret, code: codeInput)
            step = .showBackupCodes(backupCodes)
        } catch {
            verifyError = "Incorrect code — try again."
        }
    }

    public func copyBackupCodes(_ codes: [String]) {
        #if canImport(UIKit)
        UIPasteboard.general.setItems(
            [[UIPasteboard.typeAutomatic: codes.joined(separator: "\n")]],
            options: [.expirationDate: Date().addingTimeInterval(120)]
        )
        #endif
        didCopyBackupCodes = true
    }
}

// MARK: - Sheet

public struct TOTPEnrollmentSheet: View {

    @State private var vm: TOTPEnrollmentViewModel
    public var onEnrolled: () -> Void
    public var onCancel: () -> Void

    public init(api: APIClient? = nil, onEnrolled: @escaping () -> Void, onCancel: @escaping () -> Void) {
        _vm = State(wrappedValue: TOTPEnrollmentViewModel(api: api))
        self.onEnrolled = onEnrolled
        self.onCancel = onCancel
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle("Set Up 2FA")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: onCancel)
                    }
                }
        }
        .task { await vm.startSetup() }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.step {
        case .loading:
            ProgressView("Setting up…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .scanQR(let setup):
            ScanQRStep(vm: vm, setup: setup)

        case .verifying:
            ProgressView("Verifying…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .showBackupCodes(let codes):
            BackupCodesStep(vm: vm, codes: codes, onDone: onEnrolled)

        case .error(let msg):
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityHidden(true)
                Text(msg)
                    .font(.brandBodyMedium())
                    .multilineTextAlignment(.center)
                Button("Try Again") { Task { await vm.startSetup() } }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
}

// MARK: - Step 1: Scan QR

private struct ScanQRStep: View {
    @Bindable var vm: TOTPEnrollmentViewModel
    let setup: TOTPSetupResponse

    var body: some View {
        Form {
            Section {
                VStack(spacing: BrandSpacing.md) {
                    AsyncImage(url: setup.qrURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .interpolation(.none)
                                .frame(width: 200, height: 200)
                                .accessibilityLabel("QR code to scan with your authenticator app")
                        default:
                            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.md)
                                .fill(Color.bizarreSurface1)
                                .frame(width: 200, height: 200)
                                .overlay(ProgressView())
                        }
                    }

                    Text("Scan with Google Authenticator, 1Password, or iCloud Keychain")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .multilineTextAlignment(.center)

                    Button {
                        #if canImport(UIKit)
                        UIPasteboard.general.string = setup.secret
                        #endif
                    } label: {
                        Label("Copy secret key", systemImage: "doc.on.doc")
                            .font(.brandLabelSmall())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("totp.copySecret")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, BrandSpacing.sm)
            } header: {
                Text("Scan QR Code")
            }

            Section {
                HStack {
                    TextField("6-digit code", text: $vm.codeInput)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .font(.title2.monospacedDigit())
                        .accessibilityIdentifier("totp.codeField")
                    if vm.isConfirming {
                        ProgressView()
                    }
                }

                if let err = vm.verifyError {
                    Text(err)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Then enter the code to confirm")
            }

            Section {
                Button {
                    Task { await vm.confirmCode(secret: setup.secret, backupCodes: setup.backupCodes) }
                } label: {
                    Text("Verify & Enable 2FA")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.codeInput.count < 6 || vm.isConfirming)
                .accessibilityIdentifier("totp.verify")
            }
        }
    }
}

// MARK: - Step 2: Backup codes

private struct BackupCodesStep: View {
    @Bindable var vm: TOTPEnrollmentViewModel
    let codes: [String]
    var onDone: () -> Void

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                    Text("Save these backup codes somewhere safe. Each can be used once if you lose access to your authenticator app.")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }

            Section("Backup Codes") {
                ForEach(codes, id: \.self) { code in
                    Text(code)
                        .font(.brandMono())
                        .foregroundStyle(.bizarreOnSurface)
                        .accessibilityLabel("Backup code: \(code.map { String($0) }.joined(separator: " "))")
                }
            }

            Section {
                Button {
                    vm.copyBackupCodes(codes)
                } label: {
                    Label(
                        vm.didCopyBackupCodes ? "Copied!" : "Copy all codes",
                        systemImage: vm.didCopyBackupCodes ? "checkmark" : "doc.on.doc"
                    )
                    .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("totp.copyBackupCodes")

                ShareLink(item: codes.joined(separator: "\n")) {
                    Label("Export to Notes / Files", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("totp.exportCodes")
            }

            Section {
                Button {
                    onDone()
                } label: {
                    Text("Done — 2FA is enabled")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("totp.done")
            }
        }
        .navigationTitle("Backup Codes")
    }
}

// MARK: - Helpers

// TOTP calls now route through SecuritySettingsEndpoints.swift

#if DEBUG
#Preview("TOTP Enrollment") {
    TOTPEnrollmentSheet(
        api: APIClientImpl(),
        onEnrolled: { print("enrolled") },
        onCancel: { print("cancel") }
    )
}
#endif
