#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §41.3 Follow-up policy editor

/// Admin sheet: configure a sequence of automated follow-up reminders
/// (e.g. 24 h → 72 h → 168 h = 7 d) and their channel (SMS / email).
/// Each row maps to a `CreateFollowUpRequest` POSTed on save.
public struct FollowUpPolicyEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: FollowUpPolicyEditorViewModel

    public init(linkId: Int64, api: APIClient) {
        _vm = State(wrappedValue: FollowUpPolicyEditorViewModel(linkId: linkId, api: api))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                form
            }
            .navigationTitle("Follow-up reminders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        BrandHaptics.tap()
                        Task { await vm.save(); dismiss() }
                    }
                    .disabled(vm.isSaving)
                    .accessibilityIdentifier("followUp.policy.saveButton")
                }
            }
            .alert("Error", isPresented: $vm.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(vm.errorMessage ?? "Could not save follow-up policy.")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var form: some View {
        Form {
            Section {
                ForEach($vm.rules) { $rule in
                    FollowUpRuleRow(rule: $rule)
                        .accessibilityIdentifier("followUp.rule.\(rule.id)")
                }
                .onDelete { vm.removeRules(at: $0) }

                Button {
                    BrandHaptics.tap()
                    vm.addRule()
                } label: {
                    Label("Add reminder", systemImage: "plus.circle")
                        .foregroundStyle(.bizarreOrange)
                }
            } header: {
                Text("Reminder schedule")
            } footer: {
                Text("Reminders fire only if the link is still unpaid. Hours are counted from link creation.")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Rule row

struct FollowUpRuleRow: View {
    @Binding var rule: FollowUpRule

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            HStack {
                Text("Send after")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Stepper(
                    "\(rule.triggerAfterHours) h",
                    value: $rule.triggerAfterHours,
                    in: 1...720,
                    step: rule.triggerAfterHours < 24 ? 1 : 24
                )
                .accessibilityLabel("Hours before sending: \(rule.triggerAfterHours)")
            }
            Picker("Channel", selection: $rule.channel) {
                ForEach(PaymentLinkFollowUp.Channel.allCases, id: \.self) { ch in
                    Text(ch.rawValue.uppercased()).tag(ch)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Reminder channel")
        }
        .padding(.vertical, BrandSpacing.xs)
    }
}

// MARK: - FollowUpRule (editor-local model)

/// Mutable counterpart to `CreateFollowUpRequest`, used only in the editor.
public struct FollowUpRule: Identifiable, Sendable {
    public let id: UUID
    public var triggerAfterHours: Int
    public var channel: PaymentLinkFollowUp.Channel

    public init(
        id: UUID = UUID(),
        triggerAfterHours: Int = 24,
        channel: PaymentLinkFollowUp.Channel = .sms
    ) {
        self.id = id
        self.triggerAfterHours = triggerAfterHours
        self.channel = channel
    }

    func toRequest() -> CreateFollowUpRequest {
        CreateFollowUpRequest(triggerAfterHours: triggerAfterHours, channel: channel)
    }
}

// MARK: - ViewModel

@MainActor
@Observable
public final class FollowUpPolicyEditorViewModel {
    public var rules: [FollowUpRule] = [
        FollowUpRule(triggerAfterHours: 24,  channel: .sms),
        FollowUpRule(triggerAfterHours: 72,  channel: .sms),
        FollowUpRule(triggerAfterHours: 168, channel: .email)
    ]

    public private(set) var isSaving: Bool = false
    public var showError: Bool = false
    public private(set) var errorMessage: String?

    private let linkId: Int64
    private let api: APIClient

    public init(linkId: Int64, api: APIClient) {
        self.linkId = linkId
        self.api = api
    }

    public func addRule() {
        let next = (rules.last?.triggerAfterHours ?? 0) + 24
        rules.append(FollowUpRule(triggerAfterHours: next, channel: .sms))
    }

    public func removeRules(at offsets: IndexSet) {
        rules.remove(atOffsets: offsets)
    }

    public func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            for rule in rules {
                _ = try await api.createFollowUp(linkId: linkId, request: rule.toRequest())
            }
            BrandHaptics.success()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Could not save follow-up rules."
            showError = true
        }
    }
}
#endif
