#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// §4.4 — Ticket edit deep view.
//
// Editable fields: notes, estimated cost, priority, tags, discount,
// discount reason, source, referral source, due date, customer (picker
// sheet), state transition (allowed transitions from current status),
// and reassign technician.
//
// iPhone: standard NavigationStack Form sheet.
// iPad: NavigationSplitView — left column is form, right column shows a
//       live preview of the current field values (§CLAUDE.md iPad rule).

public struct TicketEditDeepView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var vm: TicketEditDeepViewModel
    @State private var pendingBanner: String?
    @State private var showingArchiveConfirm: Bool = false
    private let onSaved: () -> Void

    public init(api: APIClient, ticket: TicketDetail, onSaved: @escaping () -> Void = {}) {
        _vm = State(wrappedValue: TicketEditDeepViewModel(api: api, ticket: ticket))
        self.onSaved = onSaved
    }

    public var body: some View {
        Group {
            if Platform.isCompact {
                iPhoneBody
            } else {
                iPadBody
            }
        }
        .confirmationDialog(
            "Archive this ticket?",
            isPresented: $showingArchiveConfirm,
            titleVisibility: .visible
        ) {
            Button("Archive", role: .destructive) {
                Task { await archiveAndDismiss() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Archived tickets are hidden from the list but can be restored by an admin.")
        }
        .onChange(of: vm.didArchive) { _, archived in
            if archived { dismiss() }
        }
        .overlay(alignment: .top) {
            if let banner = pendingBanner {
                TicketPendingSyncBanner(text: banner)
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.top, BrandSpacing.sm)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(reduceMotion ? .none : BrandMotion.offlineBanner, value: pendingBanner)
            }
        }
    }

    // MARK: — iPhone layout

    private var iPhoneBody: some View {
        NavigationStack {
            editForm
                .navigationTitle("Edit Ticket")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            vm.autoSaver_cancel()
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        saveButton
                    }
                    ToolbarItem(placement: .bottomBar) {
                        Button(role: .destructive) {
                            showingArchiveConfirm = true
                        } label: {
                            Label("Archive", systemImage: "archivebox")
                                .foregroundStyle(.bizarreError)
                        }
                        .accessibilityLabel("Archive ticket")
                        .disabled(vm.isArchiving || vm.isSubmitting)
                    }
                }
        }
    }

    // MARK: — iPad layout (side-by-side form + preview)

    private var iPadBody: some View {
        NavigationStack {
            HStack(spacing: 0) {
                editForm
                    .frame(minWidth: 360, idealWidth: 420, maxWidth: 480)

                Divider()

                previewPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Edit Ticket")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        vm.autoSaver_cancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    saveButton
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button(role: .destructive) {
                        showingArchiveConfirm = true
                    } label: {
                        Label("Archive", systemImage: "archivebox")
                    }
                    .accessibilityLabel("Archive ticket")
                    .disabled(vm.isArchiving || vm.isSubmitting)
                }
            }
        }
    }

    // MARK: — Save button

    private var saveButton: some View {
        Button(vm.isSubmitting ? "Saving…" : "Save") {
            Task { await saveAndDismiss() }
        }
        .disabled(!vm.isValid || vm.isSubmitting)
        .keyboardShortcut(.return, modifiers: .command)
        .accessibilityLabel("Save ticket changes")
    }

    // MARK: — Edit form

    private var editForm: some View {
        Form {
            // Discount & pricing
            Section("Pricing") {
                LabeledFormField("Discount (USD)", text: $vm.discountText, keyboard: .decimalPad)
                    .onChange(of: vm.discountText) { _, _ in vm.pushDraft() }
                LabeledFormField("Discount reason", text: $vm.discountReason)
                    .onChange(of: vm.discountReason) { _, _ in vm.pushDraft() }
                LabeledFormField("Estimated cost (USD)", text: $vm.estimatedCost, keyboard: .decimalPad)
                    .onChange(of: vm.estimatedCost) { _, _ in vm.pushDraft() }
            }

            // Notes
            Section("Notes") {
                TextEditor(text: $vm.notes)
                    .frame(minHeight: 80)
                    .onChange(of: vm.notes) { _, _ in vm.pushDraft() }
                    .accessibilityLabel("Ticket notes")
            }

            // Attribution
            Section("Attribution") {
                LabeledFormField("Source", text: $vm.source)
                    .onChange(of: vm.source) { _, _ in vm.pushDraft() }
                LabeledFormField("Referral source", text: $vm.referralSource)
                    .onChange(of: vm.referralSource) { _, _ in vm.pushDraft() }
            }

            // Classification
            Section("Classification") {
                LabeledFormField("Priority (low/normal/high/critical)", text: $vm.priority)
                    .onChange(of: vm.priority) { _, _ in vm.pushDraft() }
                LabeledFormField("Tags (comma-separated)", text: $vm.tagsText)
                    .onChange(of: vm.tagsText) { _, _ in vm.pushDraft() }
            }

            // Scheduling
            Section("Scheduling") {
                LabeledFormField("Due on (YYYY-MM-DD)", text: $vm.dueOn,
                                 keyboard: .numbersAndPunctuation, autocapitalize: .never)
                    .onChange(of: vm.dueOn) { _, _ in vm.pushDraft() }
            }

            // State transition picker
            if !vm.allowedTransitions.isEmpty {
                Section("Advance status") {
                    ForEach(vm.allowedTransitions, id: \.self) { transition in
                        Button {
                            vm.selectedTransition = (vm.selectedTransition == transition) ? nil : transition
                        } label: {
                            HStack {
                                Label(transition.displayName, systemImage: transition.systemImage)
                                    .font(.brandBodyLarge())
                                    .foregroundStyle(.bizarreOnSurface)
                                Spacer()
                                if vm.selectedTransition == transition {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.bizarreOrange)
                                        .accessibilityLabel("Selected")
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(
                            vm.selectedTransition == transition
                                ? Color.bizarreOrange.opacity(0.1)
                                : Color.bizarreSurface1
                        )
                        .accessibilityLabel("Advance status: \(transition.displayName)")
                        .accessibilityHint(vm.selectedTransition == transition ? "Selected, tap to deselect" : "Tap to select this transition")
                    }
                }
            }

            // Error display
            if let err = vm.errorMessage {
                Section {
                    Text(err)
                        .foregroundStyle(.bizarreError)
                        .accessibilityLabel("Error: \(err)")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
    }

    // MARK: — iPad preview pane

    private var previewPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.base) {
                Text("Preview")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .padding(.bottom, BrandSpacing.sm)
                    .brandGlass(.clear, in: Capsule())
                    .padding(.horizontal, BrandSpacing.base)

                previewRow("Notes", value: vm.notes)
                previewRow("Estimated cost", value: vm.estimatedCost.isEmpty ? "—" : "$\(vm.estimatedCost)")
                previewRow("Priority", value: vm.priority.isEmpty ? "—" : vm.priority)
                previewRow("Tags", value: vm.tags.isEmpty ? "—" : vm.tags.joined(separator: ", "))
                previewRow("Discount", value: vm.discountText.isEmpty ? "—" : "$\(vm.discountText)")
                previewRow("Source", value: vm.source.isEmpty ? "—" : vm.source)
                previewRow("Referral", value: vm.referralSource.isEmpty ? "—" : vm.referralSource)
                previewRow("Due on", value: vm.dueOn.isEmpty ? "—" : vm.dueOn)

                if let transition = vm.selectedTransition {
                    Divider()
                    Label("Will advance to: \(transition.displayName)", systemImage: transition.systemImage)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOrange)
                        .padding(.horizontal, BrandSpacing.base)
                }
            }
            .padding(BrandSpacing.base)
        }
        .background(Color.bizarreSurface1.ignoresSafeArea())
    }

    private func previewRow(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
            Text(label).font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
            Text(value).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurface)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, BrandSpacing.base)
    }

    // MARK: — Actions

    private func saveAndDismiss() async {
        await vm.submit()
        guard vm.didSave else { return }
        onSaved()
        if vm.queuedOffline {
            pendingBanner = "Saved — will sync when online"
            try? await Task.sleep(nanoseconds: 900_000_000)
        }
        dismiss()
    }

    private func archiveAndDismiss() async {
        await vm.archive()
        if vm.didArchive {
            onSaved()
        }
    }
}

// MARK: - Labeled field helper (private to this file)

private struct LabeledFormField: View {
    let label: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var autocapitalize: TextInputAutocapitalization = .sentences

    init(
        _ label: String,
        text: Binding<String>,
        keyboard: UIKeyboardType = .default,
        autocapitalize: TextInputAutocapitalization = .sentences
    ) {
        self.label = label
        self._text = text
        self.keyboard = keyboard
        self.autocapitalize = autocapitalize
    }

    var body: some View {
        TextField(label, text: $text)
            .keyboardType(keyboard)
            .textInputAutocapitalization(autocapitalize)
    }
}

// MARK: - DraftAutoSaver cancel shim
// Public accessor so the view can cancel a pending debounce on dismiss
// without full DraftAutoSaver exposure in the VM.

extension TicketEditDeepViewModel {
    func autoSaver_cancel() {
        autoSaver.cancelPending()
    }
}
#endif
