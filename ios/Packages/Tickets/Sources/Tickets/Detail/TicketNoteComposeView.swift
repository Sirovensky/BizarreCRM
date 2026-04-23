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
// ViewModel is in TicketNoteComposeViewModel.swift (platform-agnostic).

public struct TicketNoteComposeView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: TicketNoteComposeViewModel
    private let onPosted: () -> Void

    public init(api: APIClient, ticketId: Int64, onPosted: @escaping () -> Void = {}) {
        _vm = State(wrappedValue: TicketNoteComposeViewModel(api: api, ticketId: ticketId))
        self.onPosted = onPosted
    }

    public var body: some View {
        NavigationStack {
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
                                Text("Write a note…")
                                    .font(.brandBodyMedium())
                                    .foregroundStyle(.bizarreOnSurfaceMuted)
                                    .padding(.top, BrandSpacing.xs)
                                    .padding(.leading, BrandSpacing.xs)
                                    .allowsHitTesting(false)
                            }
                        }
                        .accessibilityLabel("Note content")
                        .accessibilityHint("Type the note here")
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
}
#endif
