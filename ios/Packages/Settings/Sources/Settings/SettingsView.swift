import SwiftUI
import Core
import DesignSystem
import Networking
import Persistence

public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    public var onSignOut: (() -> Void)?
    @State private var showSignOutConfirm: Bool = false
    @State private var showChangeShopConfirm: Bool = false

    public init(onSignOut: (() -> Void)? = nil) {
        self.onSignOut = onSignOut
    }

    public var body: some View {
        NavigationStack {
            List {
                Section("Shop") {
                    LabeledRow(label: "Server", value: ServerURLStore.load()?.host ?? "—")
                    LabeledRow(label: "URL",    value: ServerURLStore.load()?.absoluteString ?? "—", mono: true)
                }

                Section("Security") {
                    BiometricToggleRow()
                }

                Section("App") {
                    LabeledRow(label: "Version", value: "\(Platform.appVersion) (\(Platform.buildNumber))")
                    NavigationLink("Sync diagnostics") { SyncDiagnosticsView() }
                        .accessibilityIdentifier("settings.syncDiagnostics")
                }

                Section {
                    Button(role: .destructive) {
                        showSignOutConfirm = true
                    } label: {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .accessibilityHidden(true)
                            Text("Sign out")
                        }
                        .foregroundStyle(.bizarreError)
                    }
                    .accessibilityIdentifier("settings.signOut")

                    Button(role: .destructive) {
                        showChangeShopConfirm = true
                    } label: {
                        HStack {
                            Image(systemName: "building.2")
                                .accessibilityHidden(true)
                            Text("Change shop")
                        }
                        .foregroundStyle(.bizarreError)
                    }
                    .accessibilityIdentifier("settings.changeShop")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("Settings")
            .confirmationDialog(
                "Sign out?",
                isPresented: $showSignOutConfirm,
                titleVisibility: .visible
            ) {
                Button("Sign out", role: .destructive) {
                    Task { await signOut(clearServer: false) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll need to enter your server, username and 2FA code again to sign back in.")
            }
            .confirmationDialog(
                "Change shop?",
                isPresented: $showChangeShopConfirm,
                titleVisibility: .visible
            ) {
                Button("Change shop", role: .destructive) {
                    Task { await signOut(clearServer: true) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Signs out and wipes the saved server URL so you can pick or enter a different shop.")
            }
        }
    }

    /// Best-effort server-side logout followed by a local wipe. The server
    /// call is non-fatal — if it fails (offline, 401, rate-limited), we
    /// still clear local state so the user actually ends up signed out.
    private func signOut(clearServer: Bool) async {
        if let api = APIClientHolder.current {
            _ = try? await api.logout()
        }
        TokenStore.shared.clear()
        PINStore.shared.reset()
        BiometricPreference.shared.disable()
        await APIClientHolder.current?.setAuthToken(nil)
        if clearServer {
            ServerURLStore.clear()
            await APIClientHolder.current?.setBaseURL(nil)
        }
        onSignOut?()
    }
}

/// Tiny indirection so the package doesn't have to import the App target's
/// AppServices. Wired at launch.
public enum APIClientHolder {
    nonisolated(unsafe) public static var current: APIClient?
}

// MARK: - Row helpers

private struct LabeledRow: View {
    let label: String
    let value: String
    var mono: Bool = false

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Spacer()
            Text(value)
                .font(mono ? .brandMono(size: 13) : .body)
                .foregroundStyle(.bizarreOnSurface)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }
}
