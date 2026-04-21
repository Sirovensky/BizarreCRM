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
    @State private var searchVM = SettingsSearchViewModel()
    /// Admin role gate. Caller injects real value; default is false (safe).
    public var isAdmin: Bool

    public init(onSignOut: (() -> Void)? = nil, isAdmin: Bool = false) {
        self.onSignOut = onSignOut
        self.isAdmin = isAdmin
    }

    private var isSearchActive: Bool {
        !searchVM.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // §19 Settings search — Liquid Glass search field on chrome
                SettingsSearchView(vm: searchVM) { _ in
                    // Caller handles navigation; here we just clear to dismiss results
                    searchVM.clear()
                }

                if !isSearchActive {
                    mainList
                }
            }
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

    // MARK: - Main list

    private var mainList: some View {
        List {
            // §19.1 Profile
            Section("Account") {
                NavigationLink {
                    ProfileSettingsPage(api: APIClientHolder.current)
                } label: {
                    Label("Profile", systemImage: "person.circle")
                }
                .accessibilityIdentifier("settings.profile")
            }

            // §19.5 Organization
            Section("Organization") {
                NavigationLink {
                    CompanyInfoPage(api: APIClientHolder.current)
                } label: {
                    Label("Company Info", systemImage: "building.2")
                }
                .accessibilityIdentifier("settings.companyInfo")

                NavigationLink {
                    TaxSettingsPage(api: APIClientHolder.current)
                } label: {
                    Label("Tax Settings", systemImage: "percent")
                }
                .accessibilityIdentifier("settings.tax")

                NavigationLink {
                    LanguageRegionPage(api: APIClientHolder.current)
                } label: {
                    Label("Language & Region", systemImage: "globe")
                }
                .accessibilityIdentifier("settings.languageRegion")
            }

            // §19.9 Payment methods
            Section("Payments") {
                NavigationLink {
                    PaymentMethodsPage(api: APIClientHolder.current)
                } label: {
                    Label("Payment Methods", systemImage: "creditcard")
                }
                .accessibilityIdentifier("settings.paymentMethods")
            }

            // §19.3 / §19.10 / hardware
            Section("Integrations") {
                NavigationLink {
                    NotificationsPage()
                } label: {
                    Label("Notifications", systemImage: "bell")
                }
                .accessibilityIdentifier("settings.notifications")

                NavigationLink {
                    SmsProviderPage(api: APIClientHolder.current)
                } label: {
                    Label("SMS Provider", systemImage: "message")
                }
                .accessibilityIdentifier("settings.smsProvider")

                PrinterSettingsEntryPlaceholder()
            }

            // §19.4 Appearance
            Section("Display") {
                NavigationLink {
                    AppearancePage()
                } label: {
                    Label("Appearance", systemImage: "paintbrush")
                }
                .accessibilityIdentifier("settings.appearance")
            }

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
                NavigationLink("About") { AboutView() }
                    .accessibilityIdentifier("settings.about")
            }

            // Danger zone — always visible for sign-out actions
            Section {
                NavigationLink {
                    DangerZonePage(api: APIClientHolder.current)
                } label: {
                    Label("Danger Zone", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.bizarreError)
                }
                .accessibilityIdentifier("settings.dangerZone")
            }

            // §19 Admin section — gated by role
            if isAdmin {
                Section("Admin") {
                    NavigationLink {
                        TenantAdminView(api: APIClientHolder.current)
                    } label: {
                        Label("Tenant Admin", systemImage: "building.columns")
                    }
                    .accessibilityIdentifier("settings.tenantAdmin")

                    NavigationLink {
                        FeatureFlagsView()
                    } label: {
                        Label("Feature Flags", systemImage: "flag")
                    }
                    .accessibilityIdentifier("settings.featureFlags")
                }
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
        #if canImport(UIKit)
        .listStyle(.insetGrouped)
        #endif
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
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
