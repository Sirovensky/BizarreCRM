import SwiftUI
import Networking
import DesignSystem
import Core
#if canImport(UIKit)
import UIKit
#endif

// MARK: - LeadStatusNoteSheet

/// §9.3 — Quick status-change sheet with optional note.
///
/// Presents the legal destination statuses for the lead's current status,
/// an optional free-text note, and (if status == "lost") a required lost-reason
/// picker.  Calls `PUT /api/v1/leads/{id}` via `LeadStatusNoteViewModel`.
///
/// iPhone: `.presentationDetents([.medium, .large])`.
/// iPad: side-by-side panel (status left, note right), not stacked.
public struct LeadStatusNoteSheet: View {
    @State private var vm: LeadStatusNoteViewModel
    private let onSaved: (LeadDetail) -> Void
    @Environment(\.dismiss) private var dismiss

    public init(
        api: APIClient,
        lead: LeadDetail,
        onSaved: @escaping (LeadDetail) -> Void
    ) {
        self.onSaved = onSaved
        _vm = State(wrappedValue: LeadStatusNoteViewModel(api: api, lead: lead))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                if Platform.isCompact {
                    phoneLayout
                } else {
                    padLayout
                }
            }
            .navigationTitle("Change Status")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbarContent }
        }
        .presentationDetents(Platform.isCompact ? [.medium, .large] : [.large])
        .onChange(of: vm.state.isSubmitting) { _, submitting in
            guard !submitting else { return }
            if case .saved(let detail) = vm.state {
                onSaved(detail)
                dismiss()
            }
        }
    }

    // MARK: - Layouts

    private var phoneLayout: some View {
        ScrollView {
            VStack(spacing: BrandSpacing.base) {
                statusPickerCard
                if vm.selectedStatus == "lost" { lostReasonCard }
                noteCard
                saveButton
                errorBanner
            }
            .padding(BrandSpacing.base)
        }
    }

    private var padLayout: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left column: status + lost reason
            ScrollView {
                VStack(spacing: BrandSpacing.base) {
                    statusPickerCard
                    if vm.selectedStatus == "lost" { lostReasonCard }
                    saveButton
                    errorBanner
                }
                .padding(BrandSpacing.lg)
                .frame(maxWidth: 420, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            // Right column: note entry
            ScrollView {
                noteCard
                    .padding(BrandSpacing.lg)
            }
            .frame(maxWidth: 340)
        }
    }

    // MARK: - Status picker card

    private var statusPickerCard: some View {
        cardContainer {
            sectionLabel("New Status")
            // Current status chip
            HStack(spacing: BrandSpacing.sm) {
                Text("From:")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Text(vm.currentStatus.capitalized)
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnOrange)
                    .padding(.horizontal, BrandSpacing.sm)
                    .padding(.vertical, BrandSpacing.xxs)
                    .background(Color.bizarreOrange.opacity(0.15), in: Capsule())
                    .accessibilityLabel("Current status: \(vm.currentStatus.capitalized)")
            }

            Divider().overlay(Color.bizarreOutline.opacity(0.3))

            // Destination picker — only legal transitions
            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                ForEach(vm.allowedTransitions, id: \.self) { status in
                    Button {
                        vm.selectedStatus = status
                    } label: {
                        HStack(spacing: BrandSpacing.sm) {
                            Circle()
                                .strokeBorder(
                                    vm.selectedStatus == status
                                        ? Color.bizarreOrange
                                        : Color.bizarreOutline.opacity(0.5),
                                    lineWidth: vm.selectedStatus == status ? 2 : 1
                                )
                                .background(
                                    Circle().fill(vm.selectedStatus == status
                                        ? Color.bizarreOrange
                                        : Color.clear)
                                )
                                .frame(width: 18, height: 18)
                                .accessibilityHidden(true)
                            Text(status.capitalized)
                                .font(.brandBodyLarge())
                                .foregroundStyle(
                                    vm.selectedStatus == status
                                        ? .bizarreOnSurface
                                        : .bizarreOnSurfaceMuted
                                )
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        vm.selectedStatus == status
                            ? "\(status.capitalized), selected"
                            : "Set status to \(status.capitalized)"
                    )
                    .padding(.vertical, BrandSpacing.xxs)
                }
            }
        }
    }

    // MARK: - Lost reason card

    private let kLostReasons: [(value: String, label: String)] = [
        ("price",        "Price"),
        ("competitor",   "Competitor"),
        ("no_response",  "No Response"),
        ("changed_mind", "Changed Mind"),
        ("other",        "Other"),
    ]

    private var lostReasonCard: some View {
        cardContainer {
            sectionLabel("Lost Reason (required)")
            Picker("Lost Reason", selection: $vm.lostReason) {
                Text("Select reason").tag("")
                ForEach(kLostReasons, id: \.value) { item in
                    Text(item.label).tag(item.value)
                }
            }
            .pickerStyle(.menu)
            .tint(vm.lostReason.isEmpty ? .bizarreError : .bizarreOrange)
            .accessibilityLabel("Lost reason picker")
        }
    }

    // MARK: - Note card

    private var noteCard: some View {
        cardContainer {
            sectionLabel("Note (optional)")
            TextEditor(text: $vm.note)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .frame(minHeight: 100, maxHeight: 200)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .accessibilityLabel("Status change note")
                .overlay(alignment: .topLeading) {
                    if vm.note.isEmpty {
                        Text("Add a note about this status change…")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurfaceMuted.opacity(0.5))
                            .allowsHitTesting(false)
                            .padding(.top, 4)
                    }
                }
        }
    }

    // MARK: - Save button

    private var saveButton: some View {
        Button {
            Task { await vm.save() }
        } label: {
            Group {
                if vm.state.isSubmitting {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.bizarreOnOrange)
                } else {
                    Text("Update Status")
                        .font(.brandTitleSmall())
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
        }
        .buttonStyle(.borderedProminent)
        .tint(.bizarreOrange)
        .disabled(!vm.canSave)
        .accessibilityLabel("Update lead status")
        #if canImport(UIKit)
        .keyboardShortcut(.return, modifiers: .command)
        #endif
    }

    // MARK: - Error banner

    @ViewBuilder
    private var errorBanner: some View {
        if case .failed(let msg) = vm.state {
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.bizarreError)
                    .accessibilityHidden(true)
                Text(msg)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreError)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button { vm.reset() } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .accessibilityLabel("Dismiss error")
            }
            .padding(BrandSpacing.sm)
            .background(Color.bizarreError.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.bizarreError.opacity(0.3), lineWidth: 0.5)
            )
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
                .disabled(vm.state.isSubmitting)
                .accessibilityLabel("Cancel status change")
        }
        #if canImport(UIKit)
        ToolbarItem(placement: .confirmationAction) {
            Button("Save") { Task { await vm.save() } }
                .disabled(!vm.canSave)
                .accessibilityLabel("Save status change")
        }
        #endif
    }

    // MARK: - Helpers

    private func cardContainer<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            content()
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
        )
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.brandLabelSmall())
            .foregroundStyle(.bizarreOnSurfaceMuted)
            .tracking(0.8)
    }
}
