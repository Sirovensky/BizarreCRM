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
        // §46.5 — Frequency cap: max 1 request per peer per quarter.
        if let capMessage = PeerFeedbackFrequencyCap.checkCap(
            fromEmployeeId: fromEmployeeId,
            toEmployeeId: selectedColleagueId
        ) {
            errorMessage = capMessage
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
            // Record successful request for frequency cap tracking.
            PeerFeedbackFrequencyCap.recordRequest(
                fromEmployeeId: fromEmployeeId,
                toEmployeeId: selectedColleagueId
            )
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
                    DictationTextEditor(text: $vm.whatWentWell,
                                        placeholder: "What went well?",
                                        minHeight: 72)
                }

                Section("Growth suggestion") {
                    DictationTextEditor(text: $vm.growthSuggestion,
                                        placeholder: "One area to grow…",
                                        minHeight: 72)
                }

                Section("Anything else?") {
                    DictationTextEditor(text: $vm.freeformNote,
                                        placeholder: "Optional note…",
                                        minHeight: 56)
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

// MARK: - DictationTextEditor
//
// §46.5 — Long-form text field with voice dictation microphone button.
// Available on iOS 17+ where SFSpeechRecognizer is stable for on-device use.
// Falls back to plain TextEditor on older OS versions.

private struct DictationTextEditor: View {
    @Binding var text: String
    let placeholder: String
    let minHeight: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: BrandSpacing.sm) {
            if text.isEmpty {
                TextEditor(text: $text)
                    .frame(minHeight: minHeight)
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text(placeholder)
                                .font(.brandBodyMedium())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                                .padding(.top, 8).padding(.leading, 4)
                                .allowsHitTesting(false)
                        }
                    }
                    .accessibilityLabel(placeholder)
            } else {
                TextEditor(text: $text)
                    .frame(minHeight: minHeight)
                    .accessibilityLabel(placeholder)
            }
            if #available(iOS 17.0, *) {
                VoiceDictationButton(text: $text)
                    .padding(.top, BrandSpacing.xs)
            }
        }
    }
}
