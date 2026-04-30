#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// §5.5 Customer merge view.
//
// Server contract: POST /api/v1/customers/merge { keep_id, merge_id }
//   • keep_id  — primary: survives with its own field values intact.
//   • merge_id — secondary: all tickets/invoices/SMS/contacts migrate to keep_id,
//                then the record is soft-deleted.
//   • Field preferences (name/phone/email/address/notes) shown in this UI are
//     informational — the server does NOT accept them. The diff preview lets staff
//     see which values will be lost so they can decide to edit the primary first.
//
// iPhone: bottom-sheet, step-by-step (pick candidate → review diff → confirm).
// iPad:   three-column HStack (primary | field diff | secondary) with same confirm flow.

public struct CustomerMergeView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: CustomerMergeViewModel
    @State private var showingPicker: Bool = false
    @State private var showingConfirm: Bool = false
    private let onMerged: () -> Void

    public init(api: APIClient, primary: CustomerDetail, onMerged: @escaping () -> Void = {}) {
        _vm = State(wrappedValue: CustomerMergeViewModel(api: api, primary: primary))
        self.onMerged = onMerged
    }

    public var body: some View {
        NavigationStack {
            Group {
                if Platform.isCompact {
                    iPhoneLayout
                } else {
                    iPadLayout
                }
            }
            .navigationTitle("Merge customer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityLabel("Cancel merge")
                }
                if vm.selectedCandidate != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        if vm.isMerging {
                            ProgressView()
                                .controlSize(.small)
                                .accessibilityLabel("Merging…")
                        } else {
                            Button("Merge…") { showingConfirm = true }
                                .tint(.bizarreError)
                                .accessibilityLabel("Confirm merge — irreversible")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingPicker) {
                CustomerMergeCandidatePicker(
                    query: $vm.candidateQuery,
                    results: vm.candidateResults,
                    isSearching: vm.isSearching,
                    onSelect: { candidate in
                        Task { await vm.selectCandidate(candidate) }
                    },
                    onDismiss: { showingPicker = false }
                )
            }
            .confirmationDialog(
                "Merge is permanent",
                isPresented: $showingConfirm,
                titleVisibility: .visible
            ) {
                Button("Merge (irreversible)", role: .destructive) {
                    Task {
                        await vm.performMerge()
                        if vm.mergeComplete {
                            onMerged()
                            dismiss()
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(confirmMessage)
            }
            .onChange(of: vm.candidateQuery) { _, _ in
                Task { await vm.searchCandidates() }
            }
        }
    }

    // MARK: - Confirmation message

    private var confirmMessage: String {
        let secondary = vm.selectedCandidate?.displayName ?? "the secondary customer"
        return "\(secondary)'s record will be archived. All tickets, invoices and contacts move to \(vm.primary.displayName). \(vm.primary.displayName)'s field values (name, phone, email, address) are preserved. This cannot be undone."
    }

    // MARK: - iPhone layout

    private var iPhoneLayout: some View {
        ScrollView {
            VStack(spacing: BrandSpacing.lg) {
                primaryHeader

                serverBehaviorNote

                if let err = vm.conflictMessage {
                    conflictBanner(err)
                } else if let err = vm.errorMessage {
                    errorBanner(err)
                }

                candidateSection

                if !vm.fieldRows.isEmpty {
                    fieldDiffSection
                }
            }
            .padding(BrandSpacing.base)
        }
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
    }

    // MARK: - iPad 3-column layout

    private var iPadLayout: some View {
        HStack(spacing: 0) {
            // Column 1 — Primary customer (keep)
            ScrollView {
                VStack(alignment: .leading, spacing: BrandSpacing.md) {
                    Text("Keep (primary)")
                        .font(.brandTitleMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .padding(.top, BrandSpacing.sm)
                    primaryHeader
                    serverBehaviorNote
                    if let err = vm.conflictMessage { conflictBanner(err) }
                    if let err = vm.errorMessage { errorBanner(err) }
                }
                .padding(BrandSpacing.base)
            }
            .frame(maxWidth: .infinity)
            .background(Color.bizarreSurface1)

            Divider()

            // Column 2 — Field diff (informational)
            ScrollView {
                VStack(spacing: BrandSpacing.sm) {
                    Text("Field diff (preview only)")
                        .font(.brandTitleMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, BrandSpacing.sm)

                    Text("The primary's values survive after merge. This preview shows what changes.")
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if vm.fieldRows.isEmpty {
                        Text("Select a customer to see the diff →")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, BrandSpacing.xl)
                    } else {
                        ForEach(vm.fieldRows) { row in
                            CustomerMergeFieldRowView(row: row) { winner in
                                vm.setWinner(winner, forRowId: row.id)
                            }
                            // §26.7 — keep ≥ 8pt between adjacent tappable rows
                            // so 44pt tap targets cannot overlap.
                            .adjacentRowSpacing()
                        }
                    }
                }
                .padding(BrandSpacing.base)
            }
            .frame(maxWidth: .infinity)

            Divider()

            // Column 3 — Secondary candidate (merge in)
            ScrollView {
                VStack(alignment: .leading, spacing: BrandSpacing.md) {
                    Text("Merge in (secondary)")
                        .font(.brandTitleMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .padding(.top, BrandSpacing.sm)
                    candidateSection
                }
                .padding(BrandSpacing.base)
            }
            .frame(maxWidth: .infinity)
            .background(Color.bizarreSurface1)
        }
    }

    // MARK: - Subcomponents

    private var primaryHeader: some View {
        VStack(spacing: BrandSpacing.sm) {
            customerAvatar(name: vm.primary.displayName, initials: vm.primary.initials)
            Text(vm.primary.displayName)
                .font(.brandHeadlineMedium())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityLabel("Primary customer: \(vm.primary.displayName)")
            if let email = vm.primary.email, !email.isEmpty {
                Text(email)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    /// Inline note explaining what the server actually does so staff understand
    /// the field-diff preview is informational, not a control.
    private var serverBehaviorNote: some View {
        HStack(alignment: .top, spacing: BrandSpacing.sm) {
            Image(systemName: "info.circle")
                .foregroundStyle(.bizarreTeal)
                .font(.system(size: 15))
                .accessibilityHidden(true)
            Text("After merge, **\(vm.primary.displayName)**'s name, phone, email and address are kept. All of the secondary's tickets, invoices and contacts move here.")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .padding(BrandSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreTeal.opacity(0.08), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .accessibilityElement(children: .combine)
    }

    private var candidateSection: some View {
        VStack(spacing: BrandSpacing.sm) {
            if let candidate = vm.selectedCandidate {
                VStack(spacing: BrandSpacing.sm) {
                    customerAvatar(name: candidate.displayName, initials: candidate.initials)
                    Text(candidate.displayName)
                        .font(.brandHeadlineMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .accessibilityLabel("Secondary customer: \(candidate.displayName)")
                    if let contact = candidate.contactLine {
                        Text(contact)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    Button("Change") { showingPicker = true }
                        .font(.brandLabelLarge())
                        .tint(.bizarreTeal)
                        .accessibilityLabel("Change secondary customer selection")
                }
                .frame(maxWidth: .infinity)
                .padding(BrandSpacing.md)
                .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
            } else {
                Button {
                    showingPicker = true
                } label: {
                    HStack(spacing: BrandSpacing.sm) {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 22))
                            .foregroundStyle(.bizarreOrange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Select customer to merge in")
                                .font(.brandTitleMedium())
                                .foregroundStyle(.bizarreOnSurface)
                            Text("Search by name, phone or email")
                                .font(.brandBodyMedium())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    .padding(BrandSpacing.md)
                    .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Select customer to merge in")
            }
        }
    }

    private var fieldDiffSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Field diff (preview)")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("Highlighted in orange = the value that survives. The primary's values are always kept by the server.")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)

            ForEach(vm.fieldRows) { row in
                CustomerMergeFieldRowView(row: row) { winner in
                    vm.setWinner(winner, forRowId: row.id)
                }
            }
        }
    }

    private func customerAvatar(name: String, initials: String) -> some View {
        ZStack {
            Circle().fill(Color.bizarreOrangeContainer)
            Text(initials)
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnOrange)
        }
        .frame(width: 60, height: 60)
        .accessibilityLabel("Avatar for \(name)")
        .accessibilityHidden(true)
    }

    private func conflictBanner(_ msg: String) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.bizarreWarning)
            Text(msg)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreWarning.opacity(0.12), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Conflict: \(msg)")
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.bizarreError)
            Text(msg)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreError.opacity(0.12), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(msg)")
    }
}
#endif
