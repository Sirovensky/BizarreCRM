#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

/// §2 Shared-device mode — Settings → Security → "Shared-device mode" toggle.
///
/// Shows a confirmation sheet before enabling, describing shorter sessions
/// and mandatory auto-sign-out behaviour.
///
/// Adapt layout via `Platform.isCompact`:
/// - iPhone: full-width toggle row + bottom sheet confirmation.
/// - iPad: toggle row in a Form with popover-style confirmation alert.
public struct SharedDeviceEnableView: View {

    @State private var isEnabled: Bool = false
    @State private var showConfirmation: Bool = false
    @State private var isLoading: Bool = false

    private let manager: SharedDeviceManager

    public init(manager: SharedDeviceManager = .shared) {
        self.manager = manager
    }

    public var body: some View {
        Group {
            if Platform.isCompact {
                iPhoneRow
            } else {
                iPadRow
            }
        }
        .task { isEnabled = await manager.isSharedDevice }
        .confirmationDialog(
            "Enable Shared-Device Mode?",
            isPresented: $showConfirmation,
            titleVisibility: .visible
        ) {
            Button("Enable", role: .destructive) {
                Task { await enableSharedDevice() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(warningMessage)
        }
    }

    // MARK: - iPhone layout

    private var iPhoneRow: some View {
        Toggle(isOn: toggleBinding) {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("Shared-Device Mode")
                    .font(.brandBodyLarge())
                    .foregroundStyle(Color.bizarreOnSurface)

                Text("4-hour sessions · auto sign-out · PIN required")
                    .font(.brandLabelSmall())
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
            }
        }
        .tint(Color.bizarreOrange)
        .accessibilityLabel("Shared-Device Mode")
        .accessibilityHint("When enabled, sessions are limited to 4 hours and sign-out is automatic.")
    }

    // MARK: - iPad layout

    private var iPadRow: some View {
        Toggle(isOn: toggleBinding) {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("Shared-Device Mode")
                    .font(.brandBodyLarge())
                    .foregroundStyle(Color.bizarreOnSurface)

                Text("Limits sessions to 4 hours. Requires PIN or password to re-enter after sign-out. Ideal for iPads mounted at a counter or kiosk.")
                    .font(.brandLabelSmall())
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
                    .textSelection(.enabled)
            }
        }
        .tint(Color.bizarreOrange)
        .accessibilityLabel("Shared-Device Mode")
        .accessibilityHint("When enabled, sessions are limited to 4 hours and sign-out is automatic.")
    }

    // MARK: - Toggle binding with confirmation gate

    private var toggleBinding: Binding<Bool> {
        Binding {
            isEnabled
        } set: { newValue in
            if newValue && !isEnabled {
                // Enabling: show warning first
                showConfirmation = true
            } else if !newValue && isEnabled {
                // Disabling: immediate
                Task { await disableSharedDevice() }
            }
        }
    }

    // MARK: - Actions

    private func enableSharedDevice() async {
        isLoading = true
        defer { isLoading = false }
        await manager.enable()
        isEnabled = true
    }

    private func disableSharedDevice() async {
        isLoading = true
        defer { isLoading = false }
        await manager.disable()
        isEnabled = false
    }

    // MARK: - Warning copy

    private let warningMessage = """
        Sessions will be limited to 4 hours (or the tenant-admin maximum). \
        After sign-out, a PIN or password is required to re-enter. \
        Use this mode on iPads accessible to multiple staff members.
        """
}
#endif
