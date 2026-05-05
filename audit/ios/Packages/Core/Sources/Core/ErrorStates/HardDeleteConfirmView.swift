import SwiftUI

// MARK: - §63.5 Hard-delete confirm
//
// Two tiers of confirmation for destructive hard-delete operations:
//
// 1. Standard hard-delete — `HardDeleteAlertModifier`
//    Alert with consequence copy + confirmation button.
//    Use for: delete ticket, delete customer note, remove item.
//
// 2. Catastrophic hard-delete — `CatastrophicDeleteConfirmView`
//    Full sheet; user must type the entity name to unlock Delete.
//    Use for: wipe tenant data, cancel subscription, bulk delete all.
//
// Usage (standard):
//   SomeView()
//       .hardDeleteConfirm(
//           isPresented: $showDelete,
//           entityName: "Ticket #1234",
//           consequence: "All notes and photos will be permanently removed.",
//           onConfirm: { await ticketRepo.delete(id: 1234) }
//       )
//
// Usage (catastrophic):
//   CatastrophicDeleteConfirmView(
//       entityName: "Acme Repair",
//       action: "delete all tenant data",
//       consequence: "Every ticket, customer, and invoice will be permanently erased...",
//       confirmPhrase: "Acme Repair",
//       onConfirm: { await tenantAdmin.wipeAllData() }
//   )

// MARK: - Standard hard-delete alert modifier

private struct HardDeleteAlertModifier: ViewModifier {
    @Binding var isPresented: Bool
    let entityName: String
    let consequence: String
    let onConfirm: () async -> Void

    func body(content: Content) -> some View {
        content
            .alert("Delete \(entityName)?", isPresented: $isPresented) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    Task { await onConfirm() }
                }
            } message: {
                Text(consequence)
            }
    }
}

public extension View {
    /// Presents a standard destructive-action alert requiring a single tap to confirm.
    ///
    /// - Parameters:
    ///   - isPresented: Binding controlling alert visibility.
    ///   - entityName:  Short identifier for what is being deleted (e.g. "Ticket #1234").
    ///   - consequence: One sentence explaining what data will be lost.
    ///   - onConfirm:   Async delete closure called when user taps Delete.
    func hardDeleteConfirm(
        isPresented: Binding<Bool>,
        entityName: String,
        consequence: String,
        onConfirm: @escaping () async -> Void
    ) -> some View {
        modifier(HardDeleteAlertModifier(
            isPresented: isPresented,
            entityName: entityName,
            consequence: consequence,
            onConfirm: onConfirm
        ))
    }
}

// MARK: - Catastrophic hard-delete type-to-confirm sheet

/// Full-screen confirmation flow for irreversible / catastrophic actions.
///
/// The Delete button remains disabled until `typedPhrase` exactly matches
/// `confirmPhrase` (case-sensitive). This prevents rage-taps and gives the
/// user a chance to read the consequence copy before committing.
///
/// Wrap inside a `.sheet(isPresented:)` or `.fullScreenCover(isPresented:)`.
public struct CatastrophicDeleteConfirmView: View {
    // MARK: - Inputs

    /// Short label for the thing being deleted (e.g. "Acme Repair").
    public let entityName: String

    /// What is happening — lower-case verb phrase (e.g. "delete all tenant data").
    public let action: String

    /// Full consequence paragraph shown above the text field.
    public let consequence: String

    /// The phrase the user must type exactly to unlock Delete.
    /// Defaults to `entityName` if omitted.
    public let confirmPhrase: String

    /// Async closure invoked on confirm. Sheet dismisses automatically.
    public let onConfirm: () async -> Void

    // MARK: - State

    @State private var typedPhrase = ""
    @State private var isDeleting  = false
    @Environment(\.dismiss) private var dismiss

    public init(
        entityName: String,
        action: String,
        consequence: String,
        confirmPhrase: String? = nil,
        onConfirm: @escaping () async -> Void
    ) {
        self.entityName    = entityName
        self.action        = action
        self.consequence   = consequence
        self.confirmPhrase = confirmPhrase ?? entityName
        self.onConfirm     = onConfirm
    }

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            Form {
                consequenceSection
                typeToConfirmSection
                deleteSection
            }
            .navigationTitle("Confirm deletion")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .disabled(isDeleting)
        }
    }

    // MARK: - Sections

    private var consequenceSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("This action cannot be undone", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(.red)
                    .accessibilityLabel("Warning: This action cannot be undone")

                Text(consequence)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private var typeToConfirmSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Type **\(confirmPhrase)** to confirm")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("Type to confirm", text: $typedPhrase)
                    .autocorrectionDisabled()
                    #if !os(macOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .accessibilityLabel("Type \(confirmPhrase) to confirm deletion")
            }
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                Task {
                    isDeleting = true
                    await onConfirm()
                    dismiss()
                }
            } label: {
                HStack {
                    if isDeleting {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.red)
                    }
                    Text(isDeleting ? "Deleting…" : "Delete \(entityName)")
                        .frame(maxWidth: .infinity)
                }
            }
            .disabled(!isConfirmed || isDeleting)
        }
    }

    // MARK: - Helpers

    private var isConfirmed: Bool {
        typedPhrase == confirmPhrase
    }
}

// MARK: - §63.5 Undo stack (last 5 via ⌘Z)
//
// Thin wrapper over `SceneUndoManager` that limits the displayed undo history
// to 5 entries. The scene-level undo stack (maxDepth=50) remains unchanged;
// this struct exposes only the actionable "last 5" for the ⌘Z context-menu
// quick picker available in iPad / Mac builds.
//
// Usage (from any View with @EnvironmentObject SceneUndoManager):
//   RecentUndoMenuButton(manager: undoManager)

/// Shows up to 5 recent undo actions in a menu button triggered by ⌘Z.
///
/// Placed in the navigation toolbar of Ticket / Customer / POS screens.
/// On iPhone, the same SceneUndoManager backs `.accessibilityAction(.undo)`.
public struct RecentUndoMenuButton: View {
    @Bindable var manager: SceneUndoManager

    /// Maximum undo entries to surface in the quick-picker.
    private let maxVisible = 5

    public init(manager: SceneUndoManager) {
        self.manager = manager
    }

    public var body: some View {
        if manager.canUndo {
            Menu {
                undoActions
                Divider()
                Button("Undo all (\(manager.undoCount))", role: .destructive) {
                    Task { await manager.undoAll() }
                }
                .disabled(!manager.canUndo)
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .keyboardShortcut("z", modifiers: .command)
            .accessibilityLabel("Undo recent actions")
            .help("Undo (⌘Z)")
        }
    }

    @ViewBuilder
    private var undoActions: some View {
        ForEach(manager.recentUndoDescriptions(limit: maxVisible), id: \.self) { description in
            Button {
                Task { await manager.undo() }
            } label: {
                Label("Undo \(description)", systemImage: "arrow.uturn.backward")
            }
        }
    }
}
