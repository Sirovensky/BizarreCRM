import SwiftUI
import DesignSystem

// MARK: - SettingsSection

/// A top-level group shown in the iPad 3-col sidebar.
public struct SettingsSection: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let icon: String
    public let pages: [SettingsPageEntry]

    public init(id: String, title: String, icon: String, pages: [SettingsPageEntry]) {
        self.id = id
        self.title = title
        self.icon = icon
        self.pages = pages
    }
}

// MARK: - SettingsPageEntry

/// A single navigable settings page inside a section.
public struct SettingsPageEntry: Identifiable, Equatable, Sendable {
    /// Stable accessibility / navigation identifier (e.g. "settings.profile").
    public let id: String
    public let title: String
    public let icon: String

    public init(id: String, title: String, icon: String) {
        self.id = id
        self.title = title
        self.icon = icon
    }
}

// MARK: - SettingsSectionGroups

/// Canonical grouping used by `SettingsSectionSidebar` and
/// `SettingsThreeColumnShell`.  The five groups match the §22 spec:
/// Account, Store, Team, Hardware, Developer.
public enum SettingsSectionGroups {

    public static func sections(includeAdmin: Bool) -> [SettingsSection] {
        var result: [SettingsSection] = [
            SettingsSection(
                id: "account",
                title: "Account",
                icon: "person.circle",
                pages: [
                    SettingsPageEntry(id: "settings.profile",     title: "Profile",      icon: "person.circle"),
                    SettingsPageEntry(id: "settings.preferences", title: "Preferences",  icon: "slider.horizontal.3"),
                    SettingsPageEntry(id: "settings.security",    title: "Security",     icon: "lock.shield"),
                ]
            ),
            SettingsSection(
                id: "store",
                title: "Store",
                icon: "storefront",
                pages: [
                    SettingsPageEntry(id: "settings.businessProfile", title: "Business Profile", icon: "building"),
                    SettingsPageEntry(id: "settings.companyInfo",     title: "Company Info",     icon: "building.2"),
                    SettingsPageEntry(id: "settings.tax",             title: "Tax Settings",     icon: "percent"),
                    SettingsPageEntry(id: "settings.hours",           title: "Business Hours",   icon: "clock"),
                    SettingsPageEntry(id: "settings.languageRegion",  title: "Language & Region", icon: "globe"),
                    SettingsPageEntry(id: "settings.appearance",      title: "Appearance",       icon: "paintbrush"),
                    SettingsPageEntry(id: "settings.paymentMethods",  title: "Payment Methods",  icon: "creditcard"),
                    SettingsPageEntry(id: "settings.locations",       title: "Locations",        icon: "mappin.and.ellipse"),
                ]
            ),
            SettingsSection(
                id: "team",
                title: "Team",
                icon: "person.2",
                pages: [
                    SettingsPageEntry(id: "settings.roles",        title: "Roles & Permissions", icon: "person.2.badge.key"),
                    SettingsPageEntry(id: "settings.notifications", title: "Notifications",      icon: "bell"),
                    SettingsPageEntry(id: "settings.smsProvider",  title: "SMS Provider",        icon: "message"),
                    SettingsPageEntry(id: "settings.auditLogs",    title: "Audit Logs",          icon: "list.bullet.clipboard"),
                ]
            ),
            SettingsSection(
                id: "hardware",
                title: "Hardware",
                icon: "printer",
                pages: [
                    SettingsPageEntry(id: "settings.printers",    title: "Printers",     icon: "printer"),
                    SettingsPageEntry(id: "settings.cashDrawer",  title: "Cash Drawer",  icon: "archivebox"),
                    SettingsPageEntry(id: "settings.kioskMode",   title: "Kiosk Mode",   icon: "desktopcomputer"),
                ]
            ),
            SettingsSection(
                id: "developer",
                title: "Developer",
                icon: "chevron.left.forwardslash.chevron.right",
                pages: [
                    SettingsPageEntry(id: "settings.syncDiagnostics", title: "Sync Diagnostics", icon: "antenna.radiowaves.left.and.right"),
                    SettingsPageEntry(id: "settings.about",           title: "About",             icon: "info.circle"),
                ]
            ),
        ]

        if includeAdmin {
            result.append(SettingsSection(
                id: "admin",
                title: "Admin",
                icon: "building.columns",
                pages: [
                    SettingsPageEntry(id: "settings.tenantAdmin",  title: "Tenant Admin",  icon: "building.columns"),
                    SettingsPageEntry(id: "settings.featureFlags", title: "Feature Flags", icon: "flag"),
                ]
            ))
        }

        return result
    }
}

// MARK: - SettingsSectionSidebar

/// Column 1 of the iPad 3-col settings shell.
///
/// Displays grouped section rows — Account, Store, Team, Hardware, Developer —
/// with Liquid Glass navigation chrome. Selection is bidirectionally bound to
/// the parent shell via `selectedSectionID`.
public struct SettingsSectionSidebar: View {

    let sections: [SettingsSection]

    @Binding var selectedSectionID: String?

    /// `true` while settings search is active — replaces the section list with
    /// a search-result message so the caller can overlay results in col-2.
    var isSearchActive: Bool

    public init(
        sections: [SettingsSection],
        selectedSectionID: Binding<String?>,
        isSearchActive: Bool = false
    ) {
        self.sections = sections
        self._selectedSectionID = selectedSectionID
        self.isSearchActive = isSearchActive
    }

    public var body: some View {
        List(sections, selection: $selectedSectionID) { section in
            sectionRow(section)
        }
        .listStyle(.sidebar)
        .navigationTitle("Settings")
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .overlay(alignment: .bottom) {
            if isSearchActive {
                searchActiveHint
            }
        }
        .accessibilityIdentifier("settings.sidebar")
    }

    // MARK: - Private

    @ViewBuilder
    private func sectionRow(_ section: SettingsSection) -> some View {
        Label(section.title, systemImage: section.icon)
            .tag(section.id)
            .accessibilityIdentifier("settings.sidebar.\(section.id)")
            .hoverEffect(.highlight)
    }

    private var searchActiveHint: some View {
        Text("Showing search results")
            .font(.caption2)
            .foregroundStyle(.bizarreOnSurfaceMuted)
            .padding(.vertical, BrandSpacing.xs)
            .padding(.horizontal, BrandSpacing.base)
            .frame(maxWidth: .infinity, alignment: .leading)
            .brandGlass(.clear, in: Rectangle())
            .accessibilityHidden(true)
    }
}
