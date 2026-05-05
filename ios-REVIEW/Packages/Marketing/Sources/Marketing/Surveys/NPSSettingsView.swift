import SwiftUI
import DesignSystem
import Networking
import Core

// §37.3 — NPS / CSAT settings:
//   Post-service auto-SMS link: "Rate your experience 1-5 [link]"
//   One-tap reply-with-digit for 1-5
//   Quarterly NPS: "How likely are you to recommend us 0-10?"
//   NPS send cap: max 2 / year per customer
//   Optional free-text comment after rating
//   Internal dashboard: score trend, comments feed, per-tech breakdown
//   Per-tech anonymized by default
//   Low-score (1-2 star) immediate manager push to recover
//   Recovery playbook: call within 2h

// MARK: - Settings model

public struct NPSProgramSettings: Codable, Sendable {
    /// Enable post-service auto-SMS CSAT link.
    public var csatAutoSmsEnabled: Bool
    /// Delay (hours) after ticket closes before sending CSAT link.
    public var csatSendDelayHours: Int
    /// Enable one-tap digit reply (server side; iOS just surfaces the config).
    public var csatOneTapReplyEnabled: Bool
    /// Enable quarterly NPS survey.
    public var npsEnabled: Bool
    /// Max NPS sends per customer per year (§37.3 spec: max 2).
    public var npsSendCapPerYear: Int
    /// Require free-text comment after rating.
    public var requireComment: Bool
    /// Push manager immediately when score <= this value (1-2 star threshold).
    public var managerPushThreshold: Int
    /// Show per-tech breakdown in dashboard (anonymized by default).
    public var perTechBreakdownEnabled: Bool
    /// Whether per-tech names are anonymized.
    public var perTechAnonymized: Bool

    public init(
        csatAutoSmsEnabled: Bool = true,
        csatSendDelayHours: Int = 24,
        csatOneTapReplyEnabled: Bool = true,
        npsEnabled: Bool = false,
        npsSendCapPerYear: Int = 2,
        requireComment: Bool = false,
        managerPushThreshold: Int = 2,
        perTechBreakdownEnabled: Bool = false,
        perTechAnonymized: Bool = true
    ) {
        self.csatAutoSmsEnabled = csatAutoSmsEnabled
        self.csatSendDelayHours = csatSendDelayHours
        self.csatOneTapReplyEnabled = csatOneTapReplyEnabled
        self.npsEnabled = npsEnabled
        self.npsSendCapPerYear = npsSendCapPerYear
        self.requireComment = requireComment
        self.managerPushThreshold = managerPushThreshold
        self.perTechBreakdownEnabled = perTechBreakdownEnabled
        self.perTechAnonymized = perTechAnonymized
    }

    enum CodingKeys: String, CodingKey {
        case csatAutoSmsEnabled       = "csat_auto_sms_enabled"
        case csatSendDelayHours       = "csat_send_delay_hours"
        case csatOneTapReplyEnabled   = "csat_one_tap_reply_enabled"
        case npsEnabled               = "nps_enabled"
        case npsSendCapPerYear        = "nps_send_cap_per_year"
        case requireComment           = "require_comment"
        case managerPushThreshold     = "manager_push_threshold"
        case perTechBreakdownEnabled  = "per_tech_breakdown_enabled"
        case perTechAnonymized        = "per_tech_anonymized"
    }
}

// MARK: - ViewModel

@MainActor
@Observable
public final class NPSSettingsViewModel {
    public var settings: NPSProgramSettings = .init()
    public private(set) var isLoading = true
    public private(set) var isSaving = false
    public private(set) var errorMessage: String?
    public private(set) var savedSuccessfully = false

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) { self.api = api }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            settings = try await api.getNPSSettings()
        } catch {
            AppLog.ui.warning("NPS settings fetch failed: \(error.localizedDescription, privacy: .public)")
            settings = .init()
        }
    }

    public func save() async {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        savedSuccessfully = false
        defer { isSaving = false }
        do {
            settings = try await api.updateNPSSettings(settings)
            savedSuccessfully = true
        } catch {
            errorMessage = AppError.from(error).localizedDescription
        }
    }
}

// MARK: - View

/// Settings → Surveys & Reviews → NPS settings page.
public struct NPSSettingsView: View {
    @State private var vm: NPSSettingsViewModel

    public init(api: APIClient) {
        _vm = State(wrappedValue: NPSSettingsViewModel(api: api))
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            if vm.isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Form {
                    csatSection
                    npsSection
                    dashboardSection
                    recoverySection

                    if let err = vm.errorMessage {
                        Section {
                            Text(err).foregroundStyle(.bizarreError).font(.brandBodyMedium())
                        }
                        .listRowBackground(Color.bizarreError.opacity(0.08))
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Surveys & NPS")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(vm.isSaving ? "Saving…" : "Save") {
                    Task { await vm.save() }
                }
                .disabled(vm.isSaving || vm.isLoading)
                .fontWeight(.semibold)
            }
        }
        .task { await vm.load() }
    }

    // MARK: - Sections

    private var csatSection: some View {
        Section("Post-service auto-SMS (CSAT)") {
            Toggle("Send CSAT link after ticket closes", isOn: $vm.settings.csatAutoSmsEnabled)
                .accessibilityLabel("Auto-send CSAT link: \(vm.settings.csatAutoSmsEnabled ? "on" : "off")")
            if vm.settings.csatAutoSmsEnabled {
                Stepper(value: $vm.settings.csatSendDelayHours, in: 1...72, step: 1) {
                    HStack {
                        Text("Send delay")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurface)
                        Spacer(minLength: 0)
                        Text("\(vm.settings.csatSendDelayHours)h after close")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOrange)
                            .monospacedDigit()
                    }
                }
                .accessibilityLabel("Send delay: \(vm.settings.csatSendDelayHours) hours after ticket closes")

                Toggle("One-tap reply with digit (1-5)", isOn: $vm.settings.csatOneTapReplyEnabled)
                    .accessibilityLabel("One-tap digit reply: \(vm.settings.csatOneTapReplyEnabled ? "on" : "off")")

                Toggle("Require free-text comment", isOn: $vm.settings.requireComment)
                    .accessibilityLabel("Require comment after rating: \(vm.settings.requireComment ? "on" : "off")")
            }
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    private var npsSection: some View {
        Section("Quarterly NPS survey") {
            Toggle("Enable NPS (0-10 recommendation score)", isOn: $vm.settings.npsEnabled)
                .accessibilityLabel("Enable NPS surveys: \(vm.settings.npsEnabled ? "on" : "off")")
            if vm.settings.npsEnabled {
                Stepper(value: $vm.settings.npsSendCapPerYear, in: 1...12, step: 1) {
                    HStack {
                        Text("Max sends per customer / year")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurface)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Text("\(vm.settings.npsSendCapPerYear)")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOrange)
                            .monospacedDigit()
                    }
                }
                .accessibilityLabel("Max NPS sends per year: \(vm.settings.npsSendCapPerYear)")
                Text("Recommended: max 2 per year to avoid survey fatigue.")
                    .font(.brandBodySmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    private var dashboardSection: some View {
        Section("Dashboard breakdown") {
            Toggle("Show per-tech score breakdown", isOn: $vm.settings.perTechBreakdownEnabled)
                .accessibilityLabel("Per-tech breakdown: \(vm.settings.perTechBreakdownEnabled ? "on" : "off")")
            if vm.settings.perTechBreakdownEnabled {
                Toggle("Anonymize technician names", isOn: $vm.settings.perTechAnonymized)
                    .accessibilityLabel("Anonymize technician names: \(vm.settings.perTechAnonymized ? "on" : "off")")
                Text("When on, tech names are replaced with initials in the dashboard.")
                    .font(.brandBodySmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    private var recoverySection: some View {
        Section("Low-score recovery") {
            Stepper(value: $vm.settings.managerPushThreshold, in: 1...5, step: 1) {
                HStack {
                    Text("Push manager if score ≤")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    Spacer(minLength: 0)
                    Text("\(vm.settings.managerPushThreshold) ★")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreError)
                        .monospacedDigit()
                }
            }
            .accessibilityLabel("Manager push threshold: score \(vm.settings.managerPushThreshold) or below")
            Text("Manager receives an immediate push to initiate recovery call within 2h.")
                .font(.brandBodySmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .listRowBackground(Color.bizarreSurface1)
    }
}

// MARK: - APIClient extension

public extension APIClient {
    /// `GET /api/v1/settings/nps`
    func getNPSSettings() async throws -> NPSProgramSettings {
        try await get("/api/v1/settings/nps", as: NPSProgramSettings.self)
    }

    /// `PATCH /api/v1/settings/nps`
    @discardableResult
    func updateNPSSettings(_ settings: NPSProgramSettings) async throws -> NPSProgramSettings {
        try await patch("/api/v1/settings/nps", body: settings, as: NPSProgramSettings.self)
    }
}
