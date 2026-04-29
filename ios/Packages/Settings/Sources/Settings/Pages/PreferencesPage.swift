import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - ViewModel

/// §19 Preferences page — wraps GET/PUT /settings/preferences.
/// Stores per-user UI preferences: theme, default view, compact mode, etc.
/// The preferences route lives at /settings/preferences (ENR-S6).
@MainActor
@Observable
public final class PreferencesViewModel: Sendable {

    // MARK: Preference fields — mirrors ALLOWED_PREF_KEYS on the server

    /// "system" | "light" | "dark"
    var theme: String = "system"
    /// "list" | "grid" | "kanban"
    var defaultView: String = "list"
    var timezone: String = ""
    var language: String = ""
    var sidebarCollapsed: Bool = false
    var ticketDefaultSort: String = "updated_desc"
    var ticketDefaultFilter: String = "open"
    var ticketPageSize: Int = 25
    var notificationSound: Bool = true
    var notificationDesktop: Bool = true
    var compactMode: Bool = false

    // MARK: State

    var isLoading: Bool = false
    var isSaving: Bool = false
    var errorMessage: String?
    var successMessage: String?

    // MARK: Helpers

    static let themeOptions: [(label: String, value: String)] = [
        ("System", "system"), ("Light", "light"), ("Dark", "dark"),
    ]

    static let defaultViewOptions: [(label: String, value: String)] = [
        ("List", "list"), ("Grid", "grid"), ("Kanban", "kanban"),
    ]

    static let ticketSortOptions: [(label: String, value: String)] = [
        ("Newest first", "updated_desc"),
        ("Oldest first", "updated_asc"),
        ("Customer A–Z", "customer_asc"),
    ]

    static let ticketFilterOptions: [(label: String, value: String)] = [
        ("Open", "open"), ("All", "all"), ("Closed", "closed"),
    ]

    static let pageSizeOptions: [Int] = [10, 25, 50, 100]

    // MARK: Init

    private let api: APIClient?

    public init(api: APIClient? = nil) {
        self.api = api
    }

    // MARK: API

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        guard let api else { return }
        do {
            let prefs = try await api.fetchPreferences()
            apply(prefs)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        guard let api else { return }
        do {
            let body = makeRequest()
            let prefs = try await api.updatePreferences(body)
            apply(prefs)
            successMessage = "Preferences saved."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Private

    private func apply(_ prefs: UserPreferencesResponse) {
        theme              = prefs.theme              ?? "system"
        defaultView        = prefs.defaultView        ?? "list"
        timezone           = prefs.timezone           ?? ""
        language           = prefs.language           ?? ""
        sidebarCollapsed   = prefs.sidebarCollapsed   ?? false
        ticketDefaultSort  = prefs.ticketDefaultSort  ?? "updated_desc"
        ticketDefaultFilter = prefs.ticketDefaultFilter ?? "open"
        ticketPageSize     = prefs.ticketPageSize     ?? 25
        notificationSound  = prefs.notificationSound  ?? true
        notificationDesktop = prefs.notificationDesktop ?? true
        compactMode        = prefs.compactMode        ?? false
    }

    private func makeRequest() -> UserPreferencesResponse {
        UserPreferencesResponse(
            theme: theme,
            defaultView: defaultView,
            timezone: timezone.isEmpty ? nil : timezone,
            language: language.isEmpty ? nil : language,
            sidebarCollapsed: sidebarCollapsed,
            ticketDefaultSort: ticketDefaultSort,
            ticketDefaultFilter: ticketDefaultFilter,
            ticketPageSize: ticketPageSize,
            notificationSound: notificationSound,
            notificationDesktop: notificationDesktop,
            compactMode: compactMode
        )
    }
}

// MARK: - View

public struct PreferencesPage: View {
    @State private var vm: PreferencesViewModel

    public init(api: APIClient? = nil) {
        _vm = State(initialValue: PreferencesViewModel(api: api))
    }

    public var body: some View {
        Form {
            // Theme
            Section("Theme") {
                Picker("Theme", selection: $vm.theme) {
                    ForEach(PreferencesViewModel.themeOptions, id: \.value) { opt in
                        Text(opt.label).tag(opt.value)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("App theme")
                .accessibilityIdentifier("preferences.theme")
            }

            // Display
            Section("Display") {
                Picker("Default view", selection: $vm.defaultView) {
                    ForEach(PreferencesViewModel.defaultViewOptions, id: \.value) { opt in
                        Text(opt.label).tag(opt.value)
                    }
                }
                .accessibilityIdentifier("preferences.defaultView")

                Toggle("Compact mode", isOn: $vm.compactMode)
                    .accessibilityIdentifier("preferences.compactMode")

                Toggle("Sidebar collapsed", isOn: $vm.sidebarCollapsed)
                    .accessibilityIdentifier("preferences.sidebarCollapsed")
            }

            // Tickets
            Section("Tickets") {
                Picker("Default sort", selection: $vm.ticketDefaultSort) {
                    ForEach(PreferencesViewModel.ticketSortOptions, id: \.value) { opt in
                        Text(opt.label).tag(opt.value)
                    }
                }
                .accessibilityIdentifier("preferences.ticketDefaultSort")

                Picker("Default filter", selection: $vm.ticketDefaultFilter) {
                    ForEach(PreferencesViewModel.ticketFilterOptions, id: \.value) { opt in
                        Text(opt.label).tag(opt.value)
                    }
                }
                .accessibilityIdentifier("preferences.ticketDefaultFilter")

                Picker("Page size", selection: $vm.ticketPageSize) {
                    ForEach(PreferencesViewModel.pageSizeOptions, id: \.self) { n in
                        Text("\(n) rows").tag(n)
                    }
                }
                .accessibilityIdentifier("preferences.ticketPageSize")
            }

            // Notifications
            Section("Notifications") {
                Toggle("Notification sounds", isOn: $vm.notificationSound)
                    .accessibilityIdentifier("preferences.notificationSound")
                Toggle("Desktop notifications", isOn: $vm.notificationDesktop)
                    .accessibilityIdentifier("preferences.notificationDesktop")
            }

            // Messaging — flip "SMS this customer" buttons between in-app
            // Communications and the system Messages app. iPad/iPhone can
            // never become the default SMS app, so the device branch hands
            // off via `sms:` URL. Flipping to device mode also hides the
            // SMS destination from the rail because Communications stops
            // owning conversation history.
            Section("Messaging") {
                Toggle(isOn: Binding(
                    get: { MessagingPreference.mode == .device },
                    set: { useDevice in
                        MessagingPreference.mode = useDevice ? .device : .inApp
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Use device's Messages app")
                        Text("Hands off to iOS Messages instead of in-app SMS. Disables Communications.")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
                .accessibilityIdentifier("preferences.useDeviceSMS")
            }

            // Locale overrides
            Section("Locale") {
                TextField("Timezone override (optional)", text: $vm.timezone)
                    .autocorrectionDisabled()
                    #if canImport(UIKit)
                    .autocapitalization(.none)
                    #endif
                    .accessibilityLabel("Timezone override")
                    .accessibilityIdentifier("preferences.timezone")

                TextField("Language override (optional)", text: $vm.language)
                    .autocorrectionDisabled()
                    #if canImport(UIKit)
                    .autocapitalization(.none)
                    #endif
                    .accessibilityLabel("Language override")
                    .accessibilityIdentifier("preferences.language")
            }

            if let msg = vm.errorMessage {
                Section {
                    Label(msg, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.bizarreError)
                        .accessibilityLabel("Error: \(msg)")
                }
            }

            if let msg = vm.successMessage {
                Section {
                    Label(msg, systemImage: "checkmark.circle")
                        .foregroundStyle(.bizarreSuccess)
                        .accessibilityLabel("Success: \(msg)")
                }
            }
        }
        .navigationTitle("Preferences")
        #if canImport(UIKit)
        .listStyle(.insetGrouped)
        #endif
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await vm.save() } }
                    .disabled(vm.isSaving)
                    .accessibilityIdentifier("preferences.save")
            }
        }
        .task { await vm.load() }
        .overlay {
            if vm.isLoading {
                ProgressView().accessibilityLabel("Loading preferences")
            }
        }
    }
}
