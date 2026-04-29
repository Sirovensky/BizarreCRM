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

    // MARK: iPad 3-col state

    /// Selected sidebar section on iPad (e.g. "Account", "Organization").
    @State private var selectedSection: String? = nil
    /// Selected detail page on iPad — identified by its accessibility id.
    @State private var selectedPage: String? = nil

    public init(onSignOut: (() -> Void)? = nil, isAdmin: Bool = false) {
        self.onSignOut = onSignOut
        self.isAdmin = isAdmin
    }

    private var isSearchActive: Bool {
        !searchVM.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var body: some View {
        if Platform.isCompact {
            iPhoneLayout
        } else {
            iPadLayout
        }
    }

    // MARK: - iPhone layout (unchanged)

    private var iPhoneLayout: some View {
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

    // MARK: - iPad 3-col layout

    /// Section definitions used in the iPad sidebar.
    private struct SettingsSection: Identifiable {
        let id: String
        let title: String
        let pages: [SettingsPageEntry]
    }

    private struct SettingsPageEntry: Identifiable {
        let id: String     // accessibility identifier
        let title: String
        let icon: String
    }

    private var iPadSections: [SettingsSection] {
        // §19.0 role gating: non-admins see only Account, Integrations (Notifications only),
        // Display, Help, App. Admin sections (Organization, Locations, Payments, Admin) hidden.
        var sections: [SettingsSection] = [
            SettingsSection(id: "account", title: "Account", pages: [
                SettingsPageEntry(id: "settings.profile",       title: "Profile",           icon: "person.circle"),
                SettingsPageEntry(id: "settings.security",      title: "Security",          icon: "lock.shield"),
                SettingsPageEntry(id: "settings.preferences",   title: "Preferences",       icon: "slider.horizontal.3"),
            ]),
        ]
        if isAdmin {
            sections += [
                SettingsSection(id: "organization", title: "Organization", pages: [
                    SettingsPageEntry(id: "settings.businessProfile", title: "Business Profile", icon: "building"),
                    SettingsPageEntry(id: "settings.companyInfo",   title: "Company Info",      icon: "building.2"),
                    SettingsPageEntry(id: "settings.tax",           title: "Tax Settings",      icon: "percent"),
                    SettingsPageEntry(id: "settings.hours",         title: "Business Hours",    icon: "clock"),
                    SettingsPageEntry(id: "settings.languageRegion", title: "Language & Region", icon: "globe"),
                ]),
                SettingsSection(id: "locations", title: "Locations", pages: [
                    SettingsPageEntry(id: "settings.locations",     title: "Locations",         icon: "mappin.and.ellipse"),
                ]),
                SettingsSection(id: "payments", title: "Payments", pages: [
                    SettingsPageEntry(id: "settings.paymentMethods", title: "Payment Methods",  icon: "creditcard"),
                ]),
            ]
        }
        // Integrations: Notifications always visible; SMS + printer only for admins
        var integrationPages: [SettingsPageEntry] = [
            SettingsPageEntry(id: "settings.notifications", title: "Notifications", icon: "bell"),
        ]
        if isAdmin {
            integrationPages += [
                SettingsPageEntry(id: "settings.smsProvider", title: "SMS Provider", icon: "message"),
            ]
        }
        sections.append(SettingsSection(id: "integrations", title: "Integrations", pages: integrationPages))
        sections += [
            SettingsSection(id: "display", title: "Display", pages: [
                SettingsPageEntry(id: "settings.appearance",    title: "Appearance",        icon: "paintbrush"),
            ]),
            SettingsSection(id: "help", title: "Help", pages: [
                SettingsPageEntry(id: "settings.helpCenter",    title: "Help Center",       icon: "questionmark.circle"),
                SettingsPageEntry(id: "settings.bugReport",     title: "Report a Bug",      icon: "ladybug"),
                SettingsPageEntry(id: "settings.whatsNew",      title: "What's New",        icon: "sparkles"),
            ]),
            SettingsSection(id: "app", title: "App", pages: [
                SettingsPageEntry(id: "settings.syncDiagnostics", title: "Sync Diagnostics", icon: "antenna.radiowaves.left.and.right"),
                SettingsPageEntry(id: "settings.about",         title: "About",             icon: "info.circle"),
            ]),
        ]
        if isAdmin {
            sections.append(SettingsSection(id: "admin", title: "Admin", pages: [
                SettingsPageEntry(id: "settings.tenantAdmin",   title: "Tenant Admin",      icon: "building.columns"),
                SettingsPageEntry(id: "settings.featureFlags",  title: "Feature Flags",     icon: "flag"),
            ]))
        }
        return sections
    }

    @ViewBuilder
    private func iPadDetailView(for pageId: String) -> some View {
        switch pageId {
        case "settings.profile":
            ProfileSettingsPage(api: APIClientHolder.current)
        case "settings.preferences":
            PreferencesPage(api: APIClientHolder.current)
        case "settings.businessProfile":
            BusinessProfilePage(api: APIClientHolder.current)
        case "settings.companyInfo":
            CompanyInfoPage(api: APIClientHolder.current)
        case "settings.tax":
            TaxSettingsPage(api: APIClientHolder.current)
        case "settings.hours":
            if let api = APIClientHolder.current {
                BusinessHoursEditorView(viewModel: BusinessHoursEditorViewModel(
                    repository: LiveHoursRepository(api: api)
                ))
            } else {
                ContentUnavailableView("Not connected", systemImage: "network.slash")
            }
        case "settings.languageRegion":
            LanguageRegionPage(api: APIClientHolder.current)
        case "settings.locations":
            if let api = APIClientHolder.current {
                LocationListView(repo: LiveLocationRepository(api: api))
            } else {
                ContentUnavailableView("Not connected", systemImage: "network.slash")
            }
        case "settings.paymentMethods":
            PaymentMethodsPage(api: APIClientHolder.current)
        case "settings.notifications":
            NotificationsPage()
        case "settings.smsProvider":
            SmsProviderPage(api: APIClientHolder.current)
        case "settings.security":
            SecuritySettingsPage()
        case "settings.appearance":
            AppearancePage()
        case "settings.helpCenter":
            HelpCenterView()
        case "settings.bugReport":
            BugReportSheet()
        case "settings.whatsNew":
            WhatsNewHelpView()
        case "settings.syncDiagnostics":
            SyncDiagnosticsView()
        case "settings.about":
            AboutView()
        case "settings.tenantAdmin":
            TenantAdminView(api: APIClientHolder.current)
        case "settings.featureFlags":
            FeatureFlagsView()
        default:
            ContentUnavailableView("Select a setting", systemImage: "gear")
        }
    }

    private var iPadLayout: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            // Column 1 — Section sidebar
            List(iPadSections, selection: $selectedSection) { section in
                Label(section.title, systemImage: sectionIcon(section.id))
                    .tag(section.id)
                    .accessibilityIdentifier("settings.sidebar.\(section.id)")
            }
            .navigationTitle("Settings")
            .listStyle(.sidebar)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        } content: {
            // Column 2 — Page list for selected section
            if let sectionId = selectedSection,
               let section = iPadSections.first(where: { $0.id == sectionId }) {
                List(section.pages, selection: $selectedPage) { page in
                    Label(page.title, systemImage: page.icon)
                        .tag(page.id)
                        .hoverEffect(.highlight)
                        .accessibilityIdentifier(page.id)
                }
                .navigationTitle(section.title)
                .listStyle(.insetGrouped)
                .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            } else {
                ContentUnavailableView("Select a category", systemImage: "sidebar.left")
            }
        } detail: {
            // Column 3 — Detail page
            NavigationStack {
                if let pageId = selectedPage {
                    iPadDetailView(for: pageId)
                } else {
                    ContentUnavailableView("Select a setting", systemImage: "gear")
                }
            }
        }
    }

    private func sectionIcon(_ id: String) -> String {
        switch id {
        case "account":       return "person.circle"
        case "organization":  return "building.2"
        case "locations":     return "mappin.and.ellipse"
        case "payments":      return "creditcard"
        case "integrations":  return "antenna.radiowaves.left.and.right"
        case "display":       return "paintbrush"
        case "help":          return "questionmark.circle"
        case "app":           return "apps.iphone"
        case "admin":         return "building.columns"
        default:              return "gear"
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

                NavigationLink {
                    PreferencesPage(api: APIClientHolder.current)
                } label: {
                    Label("Preferences", systemImage: "slider.horizontal.3")
                }
                .accessibilityIdentifier("settings.preferences")
            }

            // §19.5 Organization — admin-only
            // §19.0: non-admins see only Profile / Security / Notifications / Appearance / About
            if isAdmin {
                Section("Organization") {
                    NavigationLink {
                        BusinessProfilePage(api: APIClientHolder.current)
                    } label: {
                        Label("Business Profile", systemImage: "building")
                    }
                    .accessibilityIdentifier("settings.businessProfile")

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

                // §19.9 Payment methods — admin-only
                Section("Payments") {
                    NavigationLink {
                        PaymentMethodsPage(api: APIClientHolder.current)
                    } label: {
                        Label("Payment Methods", systemImage: "creditcard")
                    }
                    .accessibilityIdentifier("settings.paymentMethods")
                }
            }

            // §19.3 / §19.10 / hardware
            Section("Integrations") {
                NavigationLink {
                    NotificationsPage()
                } label: {
                    Label("Notifications", systemImage: "bell")
                }
                .accessibilityIdentifier("settings.notifications")

                // SMS provider config is admin-only; Notifications are user-facing
                if isAdmin {
                    NavigationLink {
                        SmsProviderPage(api: APIClientHolder.current)
                    } label: {
                        Label("SMS Provider", systemImage: "message")
                    }
                    .accessibilityIdentifier("settings.smsProvider")

                    PrinterSettingsEntryPlaceholder()
                }
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
                // §19.2 Auto-lock, biometric app lock, privacy snapshot
                NavigationLink {
                    SecuritySettingsPage()
                } label: {
                    Label("Security", systemImage: "lock.shield")
                }
                .accessibilityIdentifier("settings.security")
                BiometricToggleRow()
            }

            // §69 Help center
            Section("Help") {
                NavigationLink {
                    HelpCenterView()
                } label: {
                    Label("Help Center", systemImage: "questionmark.circle")
                }
                .accessibilityIdentifier("settings.helpCenter")

                NavigationLink {
                    SupportEmailComposerView()
                } label: {
                    Label("Contact Support", systemImage: "envelope")
                }
                .accessibilityIdentifier("settings.contactSupport")

                NavigationLink {
                    BugReportSheet()
                } label: {
                    Label("Report a Bug", systemImage: "ladybug")
                }
                .accessibilityIdentifier("settings.bugReport")

                NavigationLink {
                    WhatsNewHelpView()
                } label: {
                    Label("What's New", systemImage: "sparkles")
                }
                .accessibilityIdentifier("settings.whatsNew")
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

// MARK: - SettingsNavRow (§91.16 settings-row chevron polish)
//
// A navigation-row helper that renders an icon + label on the left and a
// correctly-sized, correctly-coloured chevron on the right. Use this instead
// of a raw `NavigationLink { Label(…) }` when the cell needs a custom leading
// icon background or tint, or when a non-link row must look identical to a
// navigation row (e.g. a button that presents a sheet).
//
// The chevron uses `chevron.right` at `.footnote.weight(.semibold)` with
// `.bizarreOnSurfaceMuted` tint at 0.55 opacity — matching the native `List`
// secondary-detail style across iOS 16–18 without relying on the system's
// undocumented separator override.
//
// Usage:
//   Button { showSheet = true } label: {
//       SettingsNavRow(icon: "bell", label: "Notifications")
//   }
//
//   // With a coloured icon tint and a badge:
//   SettingsNavRow(icon: "lock.shield", label: "Security",
//                  iconTint: .bizarreInfo, badgeCount: 2)

struct SettingsNavRow: View {

    let icon: String
    let label: String
    /// Optional semantic tint for the leading SF Symbol. Defaults to `.bizarreOnSurface`.
    var iconTint: Color = Color.bizarreOnSurface
    /// When non-zero, a small red count badge is shown between the label and chevron.
    var badgeCount: Int = 0

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: icon)
                .imageScale(.medium)
                .foregroundStyle(iconTint)
                .frame(width: DesignTokens.Icon.large, height: DesignTokens.Icon.large)
                .accessibilityHidden(true)

            Text(label)
                .foregroundStyle(Color.bizarreOnSurface)

            Spacer(minLength: DesignTokens.Spacing.sm)

            if badgeCount > 0 {
                Text("\(badgeCount)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, DesignTokens.Spacing.xs)
                    .padding(.vertical, 2)
                    .background(Color.bizarreError, in: Capsule())
                    .accessibilityLabel("\(badgeCount) pending")
            }

            // Chevron — matches native List disclosure indicator weight and
            // opacity. `font(.footnote.weight(.semibold))` produces the
            // system-standard › glyph size without manual frame sizing.
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.bizarreOnSurfaceMuted.opacity(0.55))
                .accessibilityHidden(true)
        }
        // Enforce WCAG 44 pt tap target height.
        .frame(minHeight: DesignTokens.Touch.minTargetSide)
        .contentShape(Rectangle())
    }
}
