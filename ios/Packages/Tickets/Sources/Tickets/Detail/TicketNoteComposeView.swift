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
// § 4.6 line 690 — @ trigger: when the user types `@`, an inline suggestion
// strip appears above the keyboard listing matching employees. Tapping a name
// inserts `@DisplayName ` at the cursor position.
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
                    VStack(alignment: .leading, spacing: 0) {
                        TextEditor(text: $vm.content)
                            .frame(minHeight: 120)
                            .overlay(alignment: .topLeading) {
                                if vm.content.isEmpty {
                                    Text("Write a note… type @ to mention someone")
                                        .font(.brandBodyMedium())
                                        .foregroundStyle(.bizarreOnSurfaceMuted)
                                        .padding(.top, BrandSpacing.xs)
                                        .padding(.leading, BrandSpacing.xs)
                                        .allowsHitTesting(false)
                                }
                            }
                            .accessibilityLabel("Note content")
                            .accessibilityHint("Type the note here. Use @ to mention a team member.")

                        // §4.6 line 690 — @ mention suggestion strip
                        if !vm.mentionSuggestions.isEmpty {
                            Divider()
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: BrandSpacing.xs) {
                                    ForEach(vm.mentionSuggestions) { employee in
                                        Button {
                                            vm.pickMention(employee)
                                        } label: {
                                            Text("@\(employee.displayName)")
                                                .font(.brandLabelLarge())
                                                .foregroundStyle(.bizarreOrange)
                                                .padding(.horizontal, BrandSpacing.sm)
                                                .padding(.vertical, BrandSpacing.xs)
                                                .background(Color.bizarreSurface2, in: Capsule())
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Mention \(employee.displayName)")
                                        .accessibilityHint("Inserts @\(employee.displayName) into the note")
                                    }
                                    Button {
                                        vm.dismissMention()
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.caption)
                                            .foregroundStyle(.bizarreOnSurfaceMuted)
                                            .padding(BrandSpacing.xs)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Dismiss mention suggestions")
                                }
                                .padding(.horizontal, BrandSpacing.xs)
                                .padding(.vertical, BrandSpacing.xs)
                            }
                            .background(Color.bizarreSurface1)
                        }
                    }
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
