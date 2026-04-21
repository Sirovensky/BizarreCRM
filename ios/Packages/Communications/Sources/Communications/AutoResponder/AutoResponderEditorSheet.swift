import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - AutoResponderEditorViewModel

@MainActor
@Observable
final class AutoResponderEditorViewModel: Sendable {
    var triggers: [String] = []
    var newTrigger: String = ""
    var reply: String = ""
    var enabled: Bool = true
    var hasTimeWindow: Bool = false
    var startHour: Int = 8
    var startMinute: Int = 0
    var endHour: Int = 20
    var endMinute: Int = 0

    private(set) var isSaving: Bool = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let api: APIClient?
    @ObservationIgnored let existingId: UUID?
    let onSave: (AutoResponderRule) -> Void

    init(rule: AutoResponderRule? = nil, api: APIClient?, onSave: @escaping (AutoResponderRule) -> Void) {
        self.api = api
        self.onSave = onSave
        if let rule {
            existingId = rule.id
            triggers   = rule.triggers
            reply      = rule.reply
            enabled    = rule.enabled
            if let s = rule.startTime, let e = rule.endTime,
               let sh = s.hour, let sm = s.minute,
               let eh = e.hour, let em = e.minute {
                hasTimeWindow = true
                startHour = sh; startMinute = sm
                endHour = eh; endMinute = em
            }
        } else {
            existingId = nil
        }
    }

    var builtRule: AutoResponderRule {
        AutoResponderRule(
            id: existingId ?? UUID(),
            triggers: triggers,
            reply: reply,
            enabled: enabled,
            startTime: hasTimeWindow ? DateComponents(hour: startHour, minute: startMinute) : nil,
            endTime: hasTimeWindow   ? DateComponents(hour: endHour,   minute: endMinute)   : nil
        )
    }

    var validationErrors: [String] { builtRule.validationErrors }
    var isValid: Bool { validationErrors.isEmpty }

    func addTrigger() {
        let t = newTrigger.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !triggers.contains(t) else { return }
        triggers.append(t)
        newTrigger = ""
    }

    func removeTrigger(_ t: String) {
        triggers.removeAll { $0 == t }
    }

    func save() async {
        guard isValid, let api else {
            onSave(builtRule) // offline / no API — caller handles persistence
            return
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let rule: AutoResponderRule
            if let eid = existingId {
                rule = try await api.patch(
                    "/api/v1/sms/auto-responders/\(eid)",
                    body: builtRule, as: AutoResponderRule.self
                )
            } else {
                rule = try await api.post(
                    "/api/v1/sms/auto-responders",
                    body: builtRule, as: AutoResponderRule.self
                )
            }
            onSave(rule)
        } catch {
            AppLog.ui.error("AutoResponder save: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - AutoResponderEditorSheet

public struct AutoResponderEditorSheet: View {
    @State private var vm: AutoResponderEditorViewModel
    @Environment(\.dismiss) private var dismiss

    public init(rule: AutoResponderRule?, api: APIClient?, onSave: @escaping (AutoResponderRule) -> Void) {
        _vm = State(wrappedValue: AutoResponderEditorViewModel(rule: rule, api: api, onSave: onSave))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                form
            }
            .navigationTitle(vm.existingId == nil ? "New Auto-Responder" : "Edit Auto-Responder")
#if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await vm.save() } }
                        .disabled(!vm.isValid || vm.isSaving)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var form: some View {
        Form {
            // MARK: Triggers
            Section {
                ForEach(vm.triggers, id: \.self) { t in
                    HStack {
                        Text(t).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurface)
                        Spacer()
                        Button {
                            vm.removeTrigger(t)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove keyword \(t)")
                    }
                }
                HStack {
                    TextField("Add keyword (e.g. STOP)", text: $vm.newTrigger)
                        .autocorrectionDisabled()
                        .onSubmit { vm.addTrigger() }
                    Button("Add") { vm.addTrigger() }
                        .disabled(vm.newTrigger.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Trigger Keywords")
            } footer: {
                Text("Message contains any of these words → rule fires (case-insensitive).")
                    .font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
            }

            // MARK: Reply
            Section("Auto-Reply") {
                TextEditor(text: $vm.reply)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .frame(minHeight: 80)
                    .scrollContentBackground(.hidden)
                    .accessibilityLabel("Auto-reply message body")
            }

            // MARK: Time window
            Section {
                Toggle("Restrict to time window", isOn: $vm.hasTimeWindow)
                    .tint(.bizarreOrange)
                if vm.hasTimeWindow {
                    HStack {
                        Text("Start").foregroundStyle(.bizarreOnSurfaceMuted)
                        Spacer()
                        Picker("Start hour", selection: $vm.startHour) {
                            ForEach(0..<24, id: \.self) { h in Text(String(format: "%02d", h)) }
                        }
                        .frame(width: 80)
                        Text(":").foregroundStyle(.bizarreOnSurfaceMuted)
                        Picker("Start minute", selection: $vm.startMinute) {
                            ForEach([0, 15, 30, 45], id: \.self) { m in Text(String(format: "%02d", m)) }
                        }
                        .frame(width: 80)
                    }
                    HStack {
                        Text("End").foregroundStyle(.bizarreOnSurfaceMuted)
                        Spacer()
                        Picker("End hour", selection: $vm.endHour) {
                            ForEach(0..<24, id: \.self) { h in Text(String(format: "%02d", h)) }
                        }
                        .frame(width: 80)
                        Text(":").foregroundStyle(.bizarreOnSurfaceMuted)
                        Picker("End minute", selection: $vm.endMinute) {
                            ForEach([0, 15, 30, 45], id: \.self) { m in Text(String(format: "%02d", m)) }
                        }
                        .frame(width: 80)
                    }
                }
            } header: {
                Text("Schedule (Quiet Hours)")
            } footer: {
                Text("Rule only fires within the time window. Outside window, messages are not replied to.")
                    .font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
            }

            // MARK: Enabled
            Section {
                Toggle("Rule enabled", isOn: $vm.enabled).tint(.bizarreOrange)
            }

            // MARK: Errors
            if !vm.validationErrors.isEmpty {
                Section {
                    ForEach(vm.validationErrors, id: \.self) { err in
                        Label(err, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.bizarreError)
                            .font(.brandBodyMedium())
                    }
                }
            }

            if let err = vm.errorMessage {
                Section {
                    Text(err).foregroundStyle(.bizarreError).font(.brandBodyMedium())
                }
            }
        }
        .scrollContentBackground(.hidden)
    }
}

// Expose existingId for view title check
extension AutoResponderEditorViewModel {
    var isEditing: Bool { existingId != nil }
    // Re-expose for sheet header
}
