import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - AppointmentReminderSettingsViewModel

@MainActor
@Observable
public final class AppointmentReminderSettingsViewModel {
    public private(set) var settings: AppointmentReminderSettings = .init()
    public private(set) var isLoading = false
    public private(set) var isSaving = false
    public private(set) var errorMessage: String?
    public var saveSuccess = false

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) { self.api = api }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            settings = try await api.fetchAppointmentReminderPolicy()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func save() async {
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        do {
            settings = try await api.updateAppointmentReminderPolicy(settings)
            saveSuccess = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func update(_ updated: AppointmentReminderSettings) {
        settings = updated
    }
}

// MARK: - AppointmentReminderSettingsView

/// Admin screen for customising reminder timing + message template.
public struct AppointmentReminderSettingsView: View {
    @State private var vm: AppointmentReminderSettingsViewModel
    @State private var draftSettings: AppointmentReminderSettings = .init()

    public init(api: APIClient) {
        _vm = State(wrappedValue: AppointmentReminderSettingsViewModel(api: api))
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            Group {
                if vm.isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Form {
                        timingSection
                        templateSection
                        quietHoursSection
                        if let err = vm.errorMessage {
                            Section {
                                Text(err).foregroundStyle(.bizarreError).font(.brandLabelSmall())
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .navigationTitle("Reminder Settings")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if vm.isSaving {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Button("Save") {
                        vm.update(draftSettings)
                        Task { await vm.save() }
                    }
                    .accessibilityLabel("Save reminder settings")
                }
            }
        }
        .task {
            await vm.load()
            draftSettings = vm.settings
        }
        .onChange(of: vm.settings) { _, s in draftSettings = s }
        .alert("Saved", isPresented: $vm.saveSuccess) {
            Button("OK", role: .cancel) {}
        }
    }

    // MARK: - Sections

    private var timingSection: some View {
        Section("Timing") {
            Stepper(
                "Send \(draftSettings.offsetHours)h before",
                value: $draftSettings.offsetHours,
                in: 1...168
            )
            .accessibilityLabel("Send reminder \(draftSettings.offsetHours) hours before appointment")
        }
    }

    private var templateSection: some View {
        Section("Message template") {
            TextEditor(text: $draftSettings.messageTemplate)
                .font(.brandMono(size: 13))
                .frame(minHeight: 100)
                .accessibilityLabel("Message template")
            Text("Tokens: {{customer_name}}, {{time}}")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    private var quietHoursSection: some View {
        Section("Quiet hours") {
            Toggle("Enable quiet hours", isOn: Binding(
                get: { draftSettings.quietHours != nil },
                set: { on in
                    draftSettings = AppointmentReminderSettings(
                        offsetHours: draftSettings.offsetHours,
                        messageTemplate: draftSettings.messageTemplate,
                        quietHours: on ? QuietHoursWindow(startHour: 21, endHour: 8) : nil
                    )
                }
            ))
            .accessibilityLabel("Enable quiet hours")

            if let qh = draftSettings.quietHours {
                Stepper("Start: \(qh.startHour):00", value: Binding(
                    get: { qh.startHour },
                    set: { v in
                        draftSettings = AppointmentReminderSettings(
                            offsetHours: draftSettings.offsetHours,
                            messageTemplate: draftSettings.messageTemplate,
                            quietHours: QuietHoursWindow(startHour: v, endHour: qh.endHour)
                        )
                    }
                ), in: 0...23)
                .accessibilityLabel("Quiet hours start: \(qh.startHour):00")

                Stepper("End: \(qh.endHour):00", value: Binding(
                    get: { qh.endHour },
                    set: { v in
                        draftSettings = AppointmentReminderSettings(
                            offsetHours: draftSettings.offsetHours,
                            messageTemplate: draftSettings.messageTemplate,
                            quietHours: QuietHoursWindow(startHour: qh.startHour, endHour: v)
                        )
                    }
                ), in: 0...23)
                .accessibilityLabel("Quiet hours end: \(qh.endHour):00")
            }
        }
    }
}
