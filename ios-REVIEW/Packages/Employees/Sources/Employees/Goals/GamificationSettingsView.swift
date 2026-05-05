import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - GamificationSettingsView
//
// §46.8 — Global opt-out for gamification celebratory UI.
// Settings → Team → Gamification.
// Tenant admin: enable/disable celebratory UI globally.
// Per-user: "Reduce celebratory UI" in Settings → Profile.
//
// Server routes (§74 gap — mark as needed):
//   GET  /api/v1/settings/gamification
//   PATCH /api/v1/settings/gamification
//   PATCH /api/v1/employees/:id/gamification-preferences  { reduce_celebratory_ui: Bool }
//
// §46.8 mandate:
//   - Global off switch for entire tenant (admin).
//   - Per-user "Reduce celebratory UI" that suppresses confetti/animations.
//   - Streak freeze guards — no milestone pop-up if employee is on approved leave.

// MARK: - Models

public struct GamificationSettings: Codable, Sendable {
    /// Tenant-level master switch. When false, all celebratory UI is suppressed for everyone.
    public var enabled: Bool
    /// Suppress milestone pop-ups for employees on approved time-off (PTO / leave).
    public var suppressOnLeave: Bool
    /// Whether employees can individually opt-out of celebratory UI.
    public var allowPerUserOptOut: Bool

    public init(
        enabled: Bool = true,
        suppressOnLeave: Bool = true,
        allowPerUserOptOut: Bool = true
    ) {
        self.enabled = enabled
        self.suppressOnLeave = suppressOnLeave
        self.allowPerUserOptOut = allowPerUserOptOut
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case suppressOnLeave    = "suppress_on_leave"
        case allowPerUserOptOut = "allow_per_user_opt_out"
    }
}

public struct GamificationPreferences: Codable, Sendable {
    /// Employee-level "reduce celebratory UI" toggle.
    public var reduceCelebratoryUI: Bool

    public init(reduceCelebratoryUI: Bool = false) {
        self.reduceCelebratoryUI = reduceCelebratoryUI
    }

    enum CodingKeys: String, CodingKey {
        case reduceCelebratoryUI = "reduce_celebratory_ui"
    }
}

// MARK: - GamificationSettingsViewModel (tenant admin)

@MainActor
@Observable
public final class GamificationSettingsViewModel {
    public var settings: GamificationSettings = .init()
    public private(set) var isLoading = false
    public private(set) var isSaving = false
    public private(set) var errorMessage: String?

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) { self.api = api }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            settings = try await api.getGamificationSettings()
        } catch {
            AppLog.ui.error("GamificationSettings load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    public func save() async {
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        do {
            settings = try await api.updateGamificationSettings(settings)
        } catch {
            AppLog.ui.error("GamificationSettings save failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - GamificationSettingsView (tenant admin panel)

public struct GamificationSettingsView: View {
    @State private var vm: GamificationSettingsViewModel

    public init(api: APIClient) {
        _vm = State(wrappedValue: GamificationSettingsViewModel(api: api))
    }

    public var body: some View {
        Form {
            Section {
                Toggle("Enable gamification", isOn: $vm.settings.enabled)
                    .accessibilityLabel("Enable badges, streaks, and celebratory animations for the whole team")
            } header: {
                Text("Global Switch")
            } footer: {
                Text(vm.settings.enabled
                     ? "Badges, streaks, and milestone celebrations are active."
                     : "All celebratory UI is suppressed team-wide. Metrics still tracked silently."
                )
                .font(.brandLabelSmall())
            }

            if vm.settings.enabled {
                Section {
                    Toggle("Suppress on approved leave", isOn: $vm.settings.suppressOnLeave)
                        .accessibilityLabel(
                            "Do not show streak or milestone pop-ups when an employee is on approved time off"
                        )
                } header: {
                    Text("Streak Freeze Guard")
                } footer: {
                    Text("Prevents milestone/streak pop-ups from appearing while an employee is on approved PTO or leave. Streaks are paused, not broken.")
                        .font(.brandLabelSmall())
                }

                Section {
                    Toggle("Allow per-user opt-out", isOn: $vm.settings.allowPerUserOptOut)
                        .accessibilityLabel("Allow each employee to reduce celebratory UI in their own settings")
                } footer: {
                    Text("When enabled, employees see a \"Reduce celebratory UI\" toggle in their profile settings.")
                        .font(.brandLabelSmall())
                }
            }

            if let err = vm.errorMessage {
                Section { Text(err).foregroundStyle(.bizarreError) }
            }
        }
        .navigationTitle("Gamification")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(vm.isSaving ? "Saving…" : "Save") {
                    Task { await vm.save() }
                }
                .disabled(vm.isSaving || vm.isLoading)
                .keyboardShortcut("s", modifiers: .command)
                .accessibilityLabel("Save gamification settings")
            }
        }
        .task { await vm.load() }
    }
}

// MARK: - GamificationPreferencesView (per-user, Settings → Profile)

@MainActor
@Observable
public final class GamificationPreferencesViewModel {
    public var prefs: GamificationPreferences = .init()
    public private(set) var isLoading = false
    public private(set) var isSaving = false
    public private(set) var errorMessage: String?

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let employeeId: Int64

    public init(api: APIClient, employeeId: Int64) {
        self.api = api
        self.employeeId = employeeId
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            prefs = try await api.getGamificationPreferences(employeeId: employeeId)
        } catch {
            AppLog.ui.error("GamificationPreferences load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    public func save() async {
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        do {
            prefs = try await api.updateGamificationPreferences(employeeId: employeeId, prefs: prefs)
        } catch {
            AppLog.ui.error("GamificationPreferences save failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}

public struct GamificationPreferencesView: View {
    @State private var vm: GamificationPreferencesViewModel

    public init(api: APIClient, employeeId: Int64) {
        _vm = State(wrappedValue: GamificationPreferencesViewModel(api: api, employeeId: employeeId))
    }

    public var body: some View {
        Form {
            Section {
                if vm.isLoading {
                    ProgressView()
                } else {
                    Toggle("Reduce celebratory UI", isOn: $vm.prefs.reduceCelebratoryUI)
                        .onChange(of: vm.prefs.reduceCelebratoryUI) { _, _ in
                            Task { await vm.save() }
                        }
                        .accessibilityLabel(
                            "Suppress confetti, animations, and milestone pop-ups for your account"
                        )
                }
            } footer: {
                Text("Disables confetti, animated badges, and milestone pop-ups. Achievements are still tracked and visible in your profile.")
                    .font(.brandLabelSmall())
            }

            if let err = vm.errorMessage {
                Section { Text(err).foregroundStyle(.bizarreError) }
            }
        }
        .navigationTitle("Celebratory UI")
        .task { await vm.load() }
    }
}

// MARK: - APIClient extensions

public extension APIClient {
    func getGamificationSettings() async throws -> GamificationSettings {
        try await get("/api/v1/settings/gamification", as: GamificationSettings.self)
    }

    func updateGamificationSettings(_ settings: GamificationSettings) async throws -> GamificationSettings {
        try await patch("/api/v1/settings/gamification", body: settings, as: GamificationSettings.self)
    }

    func getGamificationPreferences(employeeId: Int64) async throws -> GamificationPreferences {
        try await get(
            "/api/v1/employees/\(employeeId)/gamification-preferences",
            as: GamificationPreferences.self
        )
    }

    func updateGamificationPreferences(
        employeeId: Int64,
        prefs: GamificationPreferences
    ) async throws -> GamificationPreferences {
        try await patch(
            "/api/v1/employees/\(employeeId)/gamification-preferences",
            body: prefs,
            as: GamificationPreferences.self
        )
    }
}
