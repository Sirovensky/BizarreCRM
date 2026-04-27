import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - LeaderboardSettingsView
//
// §46.6 — Tenant-opt-in leaderboard configuration + per-user opt-out.
// Settings → Team → Leaderboard.
// Tenant admin: enable/disable + scope (team / location) + anonymization.
// Per-user: "Hide my name from leaderboards" in own profile settings.
//
// Server routes (§74 gap — mark as needed):
//   GET  /api/v1/settings/leaderboard
//   PATCH /api/v1/settings/leaderboard
//   PATCH /api/v1/employees/:id/leaderboard-opt-out  { opt_out: Bool }

// MARK: - Models

public struct LeaderboardSettings: Codable, Sendable {
    public var enabled: Bool
    public var scope: LeaderboardScope
    public var anonymizeOthers: Bool
    public var weeklyNotification: Bool

    public init(
        enabled: Bool = false,
        scope: LeaderboardScope = .team,
        anonymizeOthers: Bool = false,
        weeklyNotification: Bool = true
    ) {
        self.enabled = enabled
        self.scope = scope
        self.anonymizeOthers = anonymizeOthers
        self.weeklyNotification = weeklyNotification
    }

    enum CodingKeys: String, CodingKey {
        case enabled, scope
        case anonymizeOthers     = "anonymize_others"
        case weeklyNotification  = "weekly_notification"
    }
}

public enum LeaderboardScope: String, CaseIterable, Codable, Sendable {
    case team     = "team"
    case location = "location"

    public var displayName: String {
        switch self {
        case .team:     return "Whole Team"
        case .location: return "By Location"
        }
    }
}

// MARK: - LeaderboardSettingsViewModel

@MainActor
@Observable
public final class LeaderboardSettingsViewModel {
    public var settings: LeaderboardSettings = .init()
    public private(set) var isLoading = false
    public private(set) var isSaving = false
    public private(set) var errorMessage: String?

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) { self.api = api }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            settings = try await api.getLeaderboardSettings()
        } catch {
            AppLog.ui.error("LeaderboardSettings load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    public func save() async {
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        do {
            settings = try await api.updateLeaderboardSettings(settings)
        } catch {
            AppLog.ui.error("LeaderboardSettings save failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - LeaderboardSettingsView (admin / tenant settings)

public struct LeaderboardSettingsView: View {
    @State private var vm: LeaderboardSettingsViewModel

    public init(api: APIClient) {
        _vm = State(wrappedValue: LeaderboardSettingsViewModel(api: api))
    }

    public var body: some View {
        Form {
            Section {
                Toggle("Enable Leaderboard", isOn: $vm.settings.enabled)
                    .accessibilityLabel("Enable leaderboard feature for this team")
            } footer: {
                Text("Off by default. Some teams prefer not to surface internal competition metrics.")
                    .font(.brandLabelSmall())
            }

            if vm.settings.enabled {
                Section("Scope") {
                    Picker("Compare employees by", selection: $vm.settings.scope) {
                        ForEach(LeaderboardScope.allCases, id: \.self) { scope in
                            Text(scope.displayName).tag(scope)
                        }
                    }
                    .pickerStyle(.inline)
                    .accessibilityLabel("Leaderboard scope")
                }

                Section {
                    Toggle("Anonymize others", isOn: $vm.settings.anonymizeOthers)
                        .accessibilityLabel(
                            "Show initials only for colleagues — each employee always sees their own full name"
                        )
                } header: {
                    Text("Anonymization")
                } footer: {
                    Text("Each person always sees their own name. Enabling this shows colleagues as initials only, reducing pressure and comparison shaming.")
                        .font(.brandLabelSmall())
                }

                Section {
                    Toggle("Weekly summary notification", isOn: $vm.settings.weeklyNotification)
                        .accessibilityLabel("Send one weekly leaderboard summary push notification")
                } footer: {
                    Text("Sends one notification per week. Daily alerts are intentionally not supported.")
                        .font(.brandLabelSmall())
                }
            }

            if let err = vm.errorMessage {
                Section { Text(err).foregroundStyle(.bizarreError) }
            }
        }
        .navigationTitle("Leaderboard")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(vm.isSaving ? "Saving…" : "Save") {
                    Task { await vm.save() }
                }
                .disabled(vm.isSaving || vm.isLoading)
                .keyboardShortcut("s", modifiers: .command)
                .accessibilityLabel("Save leaderboard settings")
            }
        }
        .task { await vm.load() }
    }
}

// MARK: - LeaderboardOptOutView (per-user, in Settings → Profile)

@MainActor
@Observable
public final class LeaderboardOptOutViewModel {
    public var optOut: Bool = false
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
            optOut = try await api.getLeaderboardOptOut(employeeId: employeeId)
        } catch {
            AppLog.ui.error("LeaderboardOptOut load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    public func save() async {
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        do {
            optOut = try await api.setLeaderboardOptOut(employeeId: employeeId, optOut: optOut)
        } catch {
            AppLog.ui.error("LeaderboardOptOut save failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}

public struct LeaderboardOptOutView: View {
    @State private var vm: LeaderboardOptOutViewModel

    public init(api: APIClient, employeeId: Int64) {
        _vm = State(wrappedValue: LeaderboardOptOutViewModel(api: api, employeeId: employeeId))
    }

    public var body: some View {
        Form {
            Section {
                if vm.isLoading {
                    ProgressView()
                } else {
                    Toggle("Hide my name from leaderboards", isOn: $vm.optOut)
                        .onChange(of: vm.optOut) { _, _ in
                            Task { await vm.save() }
                        }
                        .accessibilityLabel(
                            "Hide your name and scores from the team leaderboard"
                        )
                }
            } footer: {
                Text("Your own view always shows your rank. This only hides your entry from colleagues' leaderboard views.")
                    .font(.brandLabelSmall())
            }

            if let err = vm.errorMessage {
                Section { Text(err).foregroundStyle(.bizarreError) }
            }
        }
        .navigationTitle("Leaderboard Privacy")
        .task { await vm.load() }
    }
}

// MARK: - APIClient extensions

public extension APIClient {
    func getLeaderboardSettings() async throws -> LeaderboardSettings {
        try await get("/api/v1/settings/leaderboard", as: LeaderboardSettings.self)
    }

    func updateLeaderboardSettings(_ settings: LeaderboardSettings) async throws -> LeaderboardSettings {
        try await patch("/api/v1/settings/leaderboard", body: settings, as: LeaderboardSettings.self)
    }

    func getLeaderboardOptOut(employeeId: Int64) async throws -> Bool {
        struct Response: Decodable { let optOut: Bool; enum CodingKeys: String, CodingKey { case optOut = "opt_out" } }
        let r = try await get("/api/v1/employees/\(employeeId)/leaderboard-opt-out", as: Response.self)
        return r.optOut
    }

    func setLeaderboardOptOut(employeeId: Int64, optOut: Bool) async throws -> Bool {
        struct Body: Encodable, Sendable { let optOut: Bool; enum CodingKeys: String, CodingKey { case optOut = "opt_out" } }
        struct Response: Decodable { let optOut: Bool; enum CodingKeys: String, CodingKey { case optOut = "opt_out" } }
        let r = try await patch(
            "/api/v1/employees/\(employeeId)/leaderboard-opt-out",
            body: Body(optOut: optOut),
            as: Response.self
        )
        return r.optOut
    }
}
