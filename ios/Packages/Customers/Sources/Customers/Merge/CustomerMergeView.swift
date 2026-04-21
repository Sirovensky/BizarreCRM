#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// §5.5 Customer merge view.
// iPhone: sheet with step-by-step layout.
// iPad: NavigationSplitView — primary column | field diff | secondary info.

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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if vm.selectedCandidate != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Merge…") { showingConfirm = true }
                            .disabled(vm.isMerging)
                            .tint(.bizarreError)
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
                Text("The secondary record will be archived and all its tickets, invoices and contacts will move to \(vm.primary.displayName). This cannot be undone.")
            }
            .onChange(of: vm.candidateQuery) { _, _ in
                Task { await vm.searchCandidates() }
            }
        }
    }

    // MARK: - iPhone layout

    private var iPhoneLayout: some View {
        ScrollView {
            VStack(spacing: BrandSpacing.lg) {
                primaryHeader

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
            // Column 1: Primary customer (keep)
            ScrollView {
                VStack(alignment: .leading, spacing: BrandSpacing.md) {
                    Text("Keep (primary)")
                        .font(.brandTitleMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .padding(.top, BrandSpacing.sm)
                    primaryHeader
                    if let err = vm.conflictMessage { conflictBanner(err) }
                    if let err = vm.errorMessage { errorBanner(err) }
                }
                .padding(BrandSpacing.base)
            }
            .frame(maxWidth: .infinity)
            .background(Color.bizarreSurface1)

            Divider()

            // Column 2: Field diff
            ScrollView {
                VStack(spacing: BrandSpacing.sm) {
                    Text("Field preferences")
                        .font(.brandTitleMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, BrandSpacing.sm)

                    if vm.fieldRows.isEmpty {
                        Text("Select a customer to merge in →")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, BrandSpacing.xl)
                    } else {
                        ForEach(vm.fieldRows) { row in
                            CustomerMergeFieldRowView(row: row) { winner in
                                vm.setWinner(winner, forRowId: row.id)
                            }
                        }
                    }
                }
                .padding(BrandSpacing.base)
            }
            .frame(maxWidth: .infinity)

            Divider()

            // Column 3: Secondary candidate (merge in)
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
            if let email = vm.primary.email, !email.isEmpty {
                Text(email)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    private var candidateSection: some View {
        VStack(spacing: BrandSpacing.sm) {
            if let candidate = vm.selectedCandidate {
                VStack(spacing: BrandSpacing.sm) {
                    customerAvatar(name: candidate.displayName, initials: candidate.initials)
                    Text(candidate.displayName)
                        .font(.brandHeadlineMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    if let contact = candidate.contactLine {
                        Text(contact)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    Button("Change") { showingPicker = true }
                        .font(.brandLabelLarge())
                        .tint(.bizarreTeal)
                }
                .frame(maxWidth: .infinity)
                .padding(BrandSpacing.md)
                .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))

                if Platform.isCompact, !vm.fieldRows.isEmpty {
                    // Field diff on iPhone is shown below in fieldDiffSection
                }
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
            Text("Field preferences")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("Tap a side to choose which value wins after the merge.")
                .font(.brandBodyMedium())
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
