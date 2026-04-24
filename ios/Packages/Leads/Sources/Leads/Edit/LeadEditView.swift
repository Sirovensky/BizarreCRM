import SwiftUI
import Networking
import DesignSystem
import Core
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Supported lead statuses

private let kLeadStatuses: [(value: String, label: String)] = [
    ("new",       "New"),
    ("contacted", "Contacted"),
    ("scheduled", "Scheduled"),
    ("qualified", "Qualified"),
    ("proposal",  "Proposal"),
    ("lost",      "Lost"),
]

private let kLeadSources: [String] = [
    "walk_in", "phone", "web", "referral", "campaign", "other",
]

private let kLostReasons: [(value: String, label: String)] = [
    ("price",        "Price"),
    ("competitor",   "Competitor"),
    ("no_response",  "No Response"),
    ("changed_mind", "Changed Mind"),
    ("other",        "Other"),
]

// MARK: - LeadEditView

/// §9 Phase 4 — Edit sheet for a lead.
/// Covers all writable fields: name, contact, pipeline status, lost reason,
/// source, and notes. Calls `PUT /api/v1/leads/{id}` via `LeadEditViewModel`.
///
/// Phone: `.presentationDetents([.large])` bottom sheet.
/// iPad: side-by-side form + status guide panel.
public struct LeadEditView: View {
    @State private var vm: LeadEditViewModel
    private let onSaved: (LeadDetail) -> Void
    @Environment(\.dismiss) private var dismiss

    public init(
        api: APIClient,
        lead: LeadDetail,
        onSaved: @escaping (LeadDetail) -> Void
    ) {
        self.onSaved = onSaved
        _vm = State(wrappedValue: LeadEditViewModel(api: api, lead: lead))
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
            .navigationTitle("Edit Lead")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbarContent }
        }
        .presentationDetents(Platform.isCompact ? [.large] : [.large])
        .onChange(of: vm.state.isSubmitting) { _, submitting in
            // When submitting flips back to false, check for success.
            guard !submitting else { return }
            if case .saved(let detail) = vm.state {
                onSaved(detail)
                dismiss()
            }
        }
    }

    // MARK: - Phone layout

    private var phoneLayout: some View {
        ScrollView {
            VStack(spacing: BrandSpacing.base) {
                formFields
                saveButton
                errorBanner
            }
            .padding(BrandSpacing.base)
        }
    }

    // MARK: - iPad layout

    private var padLayout: some View {
        HStack(spacing: 0) {
            // Left column: form (capped at 540pt)
            ScrollView {
                VStack(spacing: BrandSpacing.base) {
                    formFields
                    saveButton
                    errorBanner
                }
                .padding(BrandSpacing.lg)
                .frame(maxWidth: 540, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            // Right column: status transition guide
            ScrollView {
                statusGuide
                    .padding(BrandSpacing.lg)
            }
            .frame(maxWidth: 260)
        }
    }

    // MARK: - Shared form content

    @ViewBuilder
    private var formFields: some View {
        // Name fields
        fieldCard {
            sectionLabel("Name")
            leadTextField(
                label: "First name",
                text: $vm.firstName,
                placeholder: "First name",
                a11y: "First name field"
            )
            Divider().overlay(Color.bizarreOutline.opacity(0.3))
            leadTextField(
                label: "Last name",
                text: $vm.lastName,
                placeholder: "Last name",
                a11y: "Last name field"
            )
        }

        // Contact fields
        fieldCard {
            sectionLabel("Contact")
            phoneTextField(
                label: "Phone",
                text: $vm.phone,
                a11y: "Phone number field"
            )
            Divider().overlay(Color.bizarreOutline.opacity(0.3))
            emailTextField(
                label: "Email",
                text: $vm.email,
                a11y: "Email address field"
            )
        }

        // Status picker
        fieldCard {
            sectionLabel("Pipeline Status")
            Picker("Status", selection: $vm.status) {
                ForEach(kLeadStatuses, id: \.value) { item in
                    Text(item.label).tag(item.value)
                }
            }
            .pickerStyle(.menu)
            .tint(.bizarreOrange)
            .accessibilityLabel("Lead status picker")

            // Lost reason — only shown when status == lost
            if vm.status == "lost" {
                Divider().overlay(Color.bizarreOutline.opacity(0.3))
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

        // Source picker
        fieldCard {
            sectionLabel("Source")
            Picker("Source", selection: $vm.source) {
                Text("None").tag("")
                ForEach(kLeadSources, id: \.self) { src in
                    Text(src.replacingOccurrences(of: "_", with: " ").capitalized).tag(src)
                }
            }
            .pickerStyle(.menu)
            .tint(.bizarreOrange)
            .accessibilityLabel("Lead source picker")
        }

        // Notes
        fieldCard {
            sectionLabel("Notes")
            TextEditor(text: $vm.notes)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .frame(minHeight: 120, maxHeight: 240)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .accessibilityLabel("Lead notes")
                .overlay(alignment: .topLeading) {
                    if vm.notes.isEmpty {
                        Text("Add notes…")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurfaceMuted.opacity(0.5))
                            .allowsHitTesting(false)
                            .padding(.top, 4)
                    }
                }
        }
    }

    // MARK: - Text field helpers (platform-branched in body)

    private func leadTextField(
        label: String,
        text: Binding<String>,
        placeholder: String,
        a11y: String
    ) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Text(label)
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .frame(width: 80, alignment: .leading)
            TextField(placeholder, text: text)
                .font(.brandBodyLarge())
                .foregroundStyle(.bizarreOnSurface)
                .frame(maxWidth: .infinity)
                #if canImport(UIKit)
                .textContentType(.name)
                .textInputAutocapitalization(.words)
                #endif
                .accessibilityLabel(a11y)
        }
        .padding(.vertical, BrandSpacing.xs)
    }

    private func phoneTextField(
        label: String,
        text: Binding<String>,
        a11y: String
    ) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Text(label)
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .frame(width: 80, alignment: .leading)
            TextField(label, text: text)
                .font(.brandBodyLarge())
                .foregroundStyle(.bizarreOnSurface)
                .frame(maxWidth: .infinity)
                #if canImport(UIKit)
                .textContentType(.telephoneNumber)
                .keyboardType(.phonePad)
                .textInputAutocapitalization(.never)
                #endif
                .accessibilityLabel(a11y)
        }
        .padding(.vertical, BrandSpacing.xs)
    }

    private func emailTextField(
        label: String,
        text: Binding<String>,
        a11y: String
    ) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Text(label)
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .frame(width: 80, alignment: .leading)
            TextField(label, text: text)
                .font(.brandBodyLarge())
                .foregroundStyle(.bizarreOnSurface)
                .frame(maxWidth: .infinity)
                #if canImport(UIKit)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                #endif
                .accessibilityLabel(a11y)
        }
        .padding(.vertical, BrandSpacing.xs)
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
                    Text("Save Changes")
                        .font(.brandTitleSmall())
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
        }
        .buttonStyle(.borderedProminent)
        .tint(.bizarreOrange)
        .disabled(saveDisabled)
        .accessibilityLabel("Save lead edits")
        #if canImport(UIKit)
        .keyboardShortcut(.return, modifiers: .command)
        #endif
    }

    private var saveDisabled: Bool {
        vm.state.isSubmitting
            || (vm.status == "lost" && vm.lostReason.isEmpty)
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
                Button {
                    vm.reset()
                } label: {
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

    // MARK: - iPad: status transition guide

    private var statusGuide: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("STATUS GUIDE")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .tracking(0.8)

            ForEach(kLeadStatuses, id: \.value) { item in
                HStack(spacing: BrandSpacing.sm) {
                    Circle()
                        .fill(vm.status == item.value ? Color.bizarreOrange : Color.bizarreOutline.opacity(0.4))
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    Text(item.label)
                        .font(.brandBodyMedium())
                        .foregroundStyle(vm.status == item.value
                            ? .bizarreOnSurface
                            : .bizarreOnSurfaceMuted)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    vm.status == item.value
                        ? "\(item.label), current status"
                        : item.label
                )
            }
        }
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
                .disabled(vm.state.isSubmitting)
                .accessibilityLabel("Cancel lead edit")
        }
        #if canImport(UIKit)
        ToolbarItem(placement: .confirmationAction) {
            Button("Save") {
                Task { await vm.save() }
            }
            .disabled(saveDisabled)
            .accessibilityLabel("Save lead")
        }
        #endif
    }

    // MARK: - Helpers

    private func fieldCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            content()
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.brandLabelSmall())
            .foregroundStyle(.bizarreOnSurfaceMuted)
            .tracking(0.8)
    }
}
