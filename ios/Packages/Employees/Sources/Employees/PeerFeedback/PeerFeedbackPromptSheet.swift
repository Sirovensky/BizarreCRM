import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - PeerFeedback model

public struct PeerFeedback: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public var fromEmployeeId: String
    public var toEmployeeId: String
    public var whatWentWell: String
    public var growthSuggestion: String
    public var freeformNote: String
    public var isAnonymous: Bool
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        fromEmployeeId: String,
        toEmployeeId: String,
        whatWentWell: String = "",
        growthSuggestion: String = "",
        freeformNote: String = "",
        isAnonymous: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.fromEmployeeId = fromEmployeeId
        self.toEmployeeId = toEmployeeId
        self.whatWentWell = whatWentWell
        self.growthSuggestion = growthSuggestion
        self.freeformNote = freeformNote
        self.isAnonymous = isAnonymous
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, isAnonymous = "is_anonymous", createdAt = "created_at"
        case fromEmployeeId  = "from_employee_id"
        case toEmployeeId    = "to_employee_id"
        case whatWentWell    = "what_went_well"
        case growthSuggestion = "growth_suggestion"
        case freeformNote    = "freeform_note"
    }
}

// MARK: - PeerFeedbackPromptSheetViewModel

@MainActor
@Observable
public final class PeerFeedbackPromptSheetViewModel {
    public var selectedColleagueId: String = ""
    public var whatWentWell: String = ""
    public var growthSuggestion: String = ""
    public var freeformNote: String = ""
    public var isAnonymous: Bool = true

    public private(set) var isSaving: Bool = false
    public private(set) var errorMessage: String?

    @ObservationIgnored private let repo: any PeerFeedbackRepository
    @ObservationIgnored private let fromEmployeeId: String
    @ObservationIgnored private let onSaved: @MainActor (PeerFeedback) -> Void

    public init(
        repo: any PeerFeedbackRepository,
        fromEmployeeId: String,
        onSaved: @escaping @MainActor (PeerFeedback) -> Void
    ) {
        self.repo = repo
        self.fromEmployeeId = fromEmployeeId
        self.onSaved = onSaved
    }

    public func submit() async {
        guard !selectedColleagueId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Select a colleague."
            return
        }
        guard !whatWentWell.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Please answer \"What went well?\"."
            return
        }
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        do {
            let fb = PeerFeedback(
                fromEmployeeId: fromEmployeeId,
                toEmployeeId: selectedColleagueId,
                whatWentWell: whatWentWell,
                growthSuggestion: growthSuggestion,
                freeformNote: freeformNote,
                isAnonymous: isAnonymous
            )
            let saved = try await repo.submitFeedback(fb)
            onSaved(saved)
        } catch {
            AppLog.ui.error("PeerFeedback submit failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - PeerFeedbackPromptSheet

public struct PeerFeedbackPromptSheet: View {
    @State private var vm: PeerFeedbackPromptSheetViewModel
    @Environment(\.dismiss) private var dismiss

    /// `colleagues` is the list of eligible peer IDs shown in the picker.
    public let colleagues: [String]

    public init(
        repo: any PeerFeedbackRepository,
        fromEmployeeId: String,
        colleagues: [String],
        onSaved: @escaping @MainActor (PeerFeedback) -> Void
    ) {
        self.colleagues = colleagues
        _vm = State(wrappedValue: PeerFeedbackPromptSheetViewModel(
            repo: repo, fromEmployeeId: fromEmployeeId, onSaved: onSaved))
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Colleague") {
                    Picker("Select colleague", selection: $vm.selectedColleagueId) {
                        Text("—").tag("")
                        ForEach(colleagues, id: \.self) { id in
                            Text(id).tag(id)
                        }
                    }
                }

                Section {
                    Toggle("Anonymous", isOn: $vm.isAnonymous)
                } footer: {
                    Text("Anonymous responses are curated by the manager before being shared.")
                        .font(.footnote)
                }

                Section("What did they do well?") {
                    TextEditor(text: $vm.whatWentWell)
                        .frame(minHeight: 72)
                        .accessibilityLabel("What went well")
                }

                Section("Growth suggestion") {
                    TextEditor(text: $vm.growthSuggestion)
                        .frame(minHeight: 72)
                        .accessibilityLabel("Growth suggestion")
                }

                Section("Anything else?") {
                    TextEditor(text: $vm.freeformNote)
                        .frame(minHeight: 56)
                        .accessibilityLabel("Additional comments")
                }

                if let err = vm.errorMessage {
                    Section { Text(err).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Peer Feedback")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if vm.isSaving {
                        ProgressView()
                    } else {
                        Button("Submit") {
                            Task { await vm.submit() }
                        }
                        .keyboardShortcut(.return)
                    }
                }
            }
        }
        .presentationDetents([.large])
    }
}
