#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// §4.6 — Note compose sheet. Wired to POST /api/v1/tickets/:id/notes.
//
// iPhone: modal sheet with .presentationDetents([.medium, .large]).
// iPad:   same sheet; medium-detent gives quick-add feel on large displays.
//
// §4.6 @mention: when user types "@" in the TextEditor, a mention picker
//   floats above the keyboard showing matching employees. Selecting one
//   inserts "@firstName" at the cursor position.
//
// ViewModel is in TicketNoteComposeViewModel.swift (platform-agnostic).

public struct TicketNoteComposeView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: TicketNoteComposeViewModel
    @State private var showingMentionPicker: Bool = false
    @State private var mentionQuery: String = ""
    private let api: APIClient
    private let onPosted: () -> Void

    public init(api: APIClient, ticketId: Int64, onPosted: @escaping () -> Void = {}) {
        self.api = api
        _vm = State(wrappedValue: TicketNoteComposeViewModel(api: api, ticketId: ticketId))
        self.onPosted = onPosted
    }

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Form {
                    Section("Type") {
                        Picker("Note type", selection: $vm.type) {
                            ForEach(TicketNoteComposeViewModel.NoteType.allCases) { noteType in
                                Label(noteType.displayName, systemImage: noteType.systemImage)
                                    .tag(noteType)
                            }
                        }
                        .pickerStyle(.navigationLink)
                        .accessibilityLabel("Note type")
                    }

                    Section("Content") {
                        TextEditor(text: $vm.content)
                            .frame(minHeight: 120)
                            .overlay(alignment: .topLeading) {
                                if vm.content.isEmpty {
                                    Text("Write a note… Type @ to mention a team member")
                                        .font(.brandBodyMedium())
                                        .foregroundStyle(.bizarreOnSurfaceMuted)
                                        .padding(.top, BrandSpacing.xs)
                                        .padding(.leading, BrandSpacing.xs)
                                        .allowsHitTesting(false)
                                }
                            }
                            .onChange(of: vm.content) { _, new in
                                detectMentionTrigger(in: new)
                            }
                            .accessibilityLabel("Note content")
                            .accessibilityHint("Type the note here. Type @ to mention a team member")
                    }

                    Section("Options") {
                        Toggle(isOn: $vm.isFlagged) {
                            Label("Flag this note", systemImage: "flag.fill")
                                .foregroundStyle(.bizarreOrange)
                        }
                        .accessibilityLabel("Flag note")
                        .accessibilityHint("Flagged notes are highlighted in the timeline")
                    }

                    if let err = vm.errorMessage {
                        Section {
                            Label(err, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.bizarreError)
                                .font(.brandBodyMedium())
                                .accessibilityLabel("Error: \(err)")
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color.bizarreSurfaceBase.ignoresSafeArea())

                // §4.6 — @mention picker floats above keyboard
                if showingMentionPicker {
                    TicketNoteMentionPicker(
                        api: api,
                        query: mentionQuery,
                        onSelect: { candidate in
                            insertMention(candidate)
                        },
                        onDismiss: {
                            showingMentionPicker = false
                        }
                    )
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.bottom, BrandSpacing.base)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(10)
                }
            }
            .animation(.spring(duration: 0.2), value: showingMentionPicker)
            .navigationTitle("Add Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityLabel("Cancel adding note")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(vm.isSubmitting ? "Posting…" : "Post") {
                        Task {
                            await vm.post()
                            if vm.didPost {
                                BrandHaptics.success()
                                onPosted()
                                dismiss()
                            }
                        }
                    }
                    .disabled(!vm.isValid || vm.isSubmitting)
                    .keyboardShortcut(.return, modifiers: .command)
                    .accessibilityLabel(vm.isSubmitting ? "Posting note" : "Post note")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - @mention detection

    /// Detects whether the last inserted character is "@" and shows the picker.
    private func detectMentionTrigger(in text: String) {
        // Look for @ followed by letters at the end of the string (or before whitespace)
        guard let atIdx = text.lastIndex(of: "@") else {
            if showingMentionPicker { showingMentionPicker = false }
            return
        }
        let afterAt = text[text.index(after: atIdx)...]
        // If the text after @ contains whitespace, the mention is complete
        if afterAt.contains(where: { $0.isWhitespace }) {
            if showingMentionPicker { showingMentionPicker = false }
            return
        }
        mentionQuery = String(afterAt)
        showingMentionPicker = true
    }

    /// Replaces the "@query" fragment in the content with "@firstName ".
    private func insertMention(_ candidate: MentionCandidate) {
        guard let atIdx = vm.content.lastIndex(of: "@") else { return }
        let beforeAt = String(vm.content[..<atIdx])
        vm.content = beforeAt + candidate.mentionToken + " "
        showingMentionPicker = false
    }
}
#endif
