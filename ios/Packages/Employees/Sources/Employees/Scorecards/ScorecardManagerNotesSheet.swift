import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - ScorecardManagerNote

public struct ScorecardManagerNote: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public var text: String
    public var noteType: NoteType
    public var createdAt: Date

    public enum NoteType: String, Codable, CaseIterable, Sendable {
        case praise   = "praise"
        case coaching = "coaching"

        public var displayName: String {
            switch self {
            case .praise:   return "Praise"
            case .coaching: return "Coaching"
            }
        }
    }

    public init(id: String = UUID().uuidString, text: String, noteType: NoteType, createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.noteType = noteType
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, text
        case noteType  = "note_type"
        case createdAt = "created_at"
    }
}

// MARK: - ScorecardManagerNotesSheetViewModel

@MainActor
@Observable
public final class ScorecardManagerNotesSheetViewModel {
    public var noteText: String = ""
    public var noteType: ScorecardManagerNote.NoteType = .praise
    public private(set) var isSaving: Bool = false
    public private(set) var errorMessage: String?

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let employeeId: String
    @ObservationIgnored private let onSaved: @MainActor (ScorecardManagerNote) -> Void

    public init(api: APIClient, employeeId: String, onSaved: @escaping @MainActor (ScorecardManagerNote) -> Void) {
        self.api = api
        self.employeeId = employeeId
        self.onSaved = onSaved
    }

    public func save() async {
        guard !noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Note cannot be empty."
            return
        }
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        // Server call would go here; optimistic local return for now.
        let note = ScorecardManagerNote(text: noteText, noteType: noteType)
        onSaved(note)
    }
}

// MARK: - ScorecardManagerNotesSheet

public struct ScorecardManagerNotesSheet: View {
    @State private var vm: ScorecardManagerNotesSheetViewModel
    @Environment(\.dismiss) private var dismiss

    public init(api: APIClient, employeeId: String, onSaved: @escaping @MainActor (ScorecardManagerNote) -> Void) {
        _vm = State(wrappedValue: ScorecardManagerNotesSheetViewModel(api: api, employeeId: employeeId, onSaved: onSaved))
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Note Type") {
                    Picker("Type", selection: $vm.noteType) {
                        ForEach(ScorecardManagerNote.NoteType.allCases, id: \.self) { t in
                            Label(t.displayName, systemImage: t == .praise ? "hand.thumbsup" : "person.crop.circle.badge.questionmark")
                                .tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Note") {
                    TextEditor(text: $vm.noteText)
                        .frame(minHeight: 100)
                        .accessibilityLabel("Manager note text")
                }

                if let err = vm.errorMessage {
                    Section { Text(err).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Add Note")
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
                        Button("Save") {
                            Task { await vm.save(); dismiss() }
                        }
                        .keyboardShortcut(.return)
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
