import SwiftUI
import Core
import DesignSystem
import Networking
import Persistence

public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    public var onSignOut: (() -> Void)?
    @State private var showSignOutConfirm: Bool = false

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
                            Text("Sign out")
                        }
                        .foregroundStyle(.bizarreError)
                    }
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
                    Task { await signOut() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll need to enter your server, username and 2FA code again to sign back in.")
            }
        }
    }

    private func signOut() async {
        TokenStore.shared.clear()
        PINStore.shared.reset()
        await APIClientHolder.current?.setAuthToken(nil)
        // Server URL stays — user typically logs back into the same shop.
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
