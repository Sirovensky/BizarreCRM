import SwiftUI
import DesignSystem
import Core

// MARK: - ConflictDiffView

/// Side-by-side local vs server diff with per-field "take this" radio buttons
/// and a resolution picker at the bottom.
///
/// Supports iPhone (vertical scroll) and iPad (two-column layout).
public struct ConflictDiffView: View {
    let initialConflict: ConflictItem
    @Bindable var viewModel: ConflictResolutionViewModel

    @State private var chosenResolution: Resolution = .keepServer
    @State private var showResolutionSheet: Bool = false
    @Environment(\.dismiss) private var dismiss

    public init(initialConflict: ConflictItem, viewModel: ConflictResolutionViewModel) {
        self.initialConflict = initialConflict
        self.viewModel = viewModel
    }

    // MARK: - Body

    public var body: some View {
        Group {
            if case .resolving = viewModel.phase, viewModel.selectedConflict == nil {
                ProgressView("Loading conflict details…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Loading conflict details")
            } else if let conflict = viewModel.selectedConflict {
                mainContent(conflict)
            } else {
                // Fallback: use the list-level item without version JSON.
                mainContent(initialConflict)
            }
        }
        .navigationTitle("Review Conflict")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarItems }
        .sheet(isPresented: $showResolutionSheet) {
            resolutionSheet
        }
        .onChange(of: viewModel.phase) { _, newPhase in
            if case .resolved = newPhase { dismiss() }
        }
    }

    // MARK: - Main content

    private func mainContent(_ conflict: ConflictItem) -> some View {
        ScrollView {
            VStack(spacing: BrandSpacing.lg) {
                conflictHeader(conflict)
                diffBody(conflict)
                resolutionFooter(conflict)
            }
            .padding(BrandSpacing.base)
        }
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
    }

    // MARK: - Header

    private func conflictHeader(_ conflict: ConflictItem) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text("\(conflict.entityKind.capitalized) #\(conflict.entityId)")
                        .font(.brandTitleLarge())
                        .foregroundStyle(.bizarreOnSurface)
                    Text(conflict.conflictType.displayName)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                Spacer()
                statusChip(conflict.status)
            }
            Text("Reported by \(conflict.reporterDisplayName)")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .padding(BrandSpacing.base)
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Diff body

    @ViewBuilder
    private func diffBody(_ conflict: ConflictItem) -> some View {
        let fields = conflict.diffedFields
        if fields.isEmpty {
            Text("Field-level diff unavailable — version JSON not included in this response.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(BrandSpacing.base)
                .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        } else {
            diffFieldsSection(fields)
        }
    }

    private func diffFieldsSection(_ fields: [ConflictField]) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            // Column header row
            if !Platform.isCompact {
                diffColumnHeader
                    .padding(.horizontal, BrandSpacing.sm)
            }

            ForEach(fields) { field in
                ConflictFieldRow(
                    field: field,
                    selectedSide: Binding(
                        get: { viewModel.fieldSelections[field.key] ?? .server },
                        set: { viewModel.selectSide($0, for: field.key) }
                    ),
                    isCompact: Platform.isCompact
                )
            }
        }
    }

    private var diffColumnHeader: some View {
        HStack(spacing: 0) {
            Text("Field")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Local")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .frame(maxWidth: .infinity, alignment: .center)
            Text("Server")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, BrandSpacing.sm)
    }

    // MARK: - Resolution footer

    private func resolutionFooter(_ conflict: ConflictItem) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Resolution")
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreOnSurface)

            // Resolution strategy picker
            Picker("Resolution", selection: $chosenResolution) {
                ForEach(Resolution.allCases.filter { $0 != .rejected }, id: \.self) { r in
                    Text(r.displayName).tag(r)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Choose resolution strategy")

            // Notes field
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("Notes (optional)")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                TextField("Add resolution notes…", text: $viewModel.resolutionNotes, axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.roundedBorder)
                    .font(.brandBodyMedium())
                    .accessibilityLabel("Resolution notes")
            }

            // Submit button
            Button {
                showResolutionSheet = true
            } label: {
                HStack {
                    Spacer()
                    if case .resolving = viewModel.phase {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Resolve Conflict")
                            .font(.brandLabelLarge())
                            .foregroundStyle(.white)
                    }
                    Spacer()
                }
                .padding(.vertical, BrandSpacing.sm)
            }
            .buttonStyle(.borderedProminent)
            .tint(.bizarreTeal)
            .disabled({ if case .resolving = viewModel.phase { return true } else { return false } }())
            .accessibilityLabel("Resolve conflict")
            .accessibilityHint("Submit your resolution choice for this conflict")
        }
        .padding(BrandSpacing.base)
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
    }

    // MARK: - Resolution confirmation sheet

    private var resolutionSheet: some View {
        NavigationStack {
            VStack(spacing: BrandSpacing.lg) {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 48))
                    .foregroundStyle(.bizarreTeal)
                    .accessibilityHidden(true)

                Text("Confirm Resolution")
                    .font(.brandTitleLarge())
                    .foregroundStyle(.bizarreOnSurface)

                Text("Resolution: **\(chosenResolution.displayName)**")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)

                if let conflict = viewModel.selectedConflict ?? Optional(initialConflict) {
                    Text("This will mark conflict #\(conflict.id) as resolved. The chosen version must be replayed via the entity's own endpoint.")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: BrandSpacing.base) {
                    Button("Cancel", role: .cancel) {
                        showResolutionSheet = false
                    }
                    .buttonStyle(.bordered)
                    .tint(.bizarreOnSurfaceMuted)

                    Button("Confirm") {
                        showResolutionSheet = false
                        let cid = viewModel.selectedConflict?.id ?? initialConflict.id
                        Task {
                            await viewModel.submitResolution(
                                conflictId: cid,
                                resolution: chosenResolution
                            )
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.bizarreTeal)
                }
            }
            .padding(BrandSpacing.xl)
            .navigationTitle("Confirm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showResolutionSheet = false }
                }
            }
            .presentationDetents([.medium])
        }
        .accessibilityLabel("Confirm resolution sheet")
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Close") { dismiss() }
                .accessibilityLabel("Close conflict review")
        }
    }

    // MARK: - Helpers

    private func statusChip(_ status: ConflictStatus) -> some View {
        Text(status.displayName)
            .font(.brandMono(size: 11))
            .foregroundStyle(status == .pending ? Color.bizarreWarning : Color.bizarreOnSurfaceMuted)
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, BrandSpacing.xxs)
            .background(
                (status == .pending ? Color.bizarreWarning : Color.bizarreOnSurfaceMuted).opacity(0.15),
                in: Capsule()
            )
            .accessibilityLabel("Status: \(status.displayName)")
    }
}

// MARK: - ConflictFieldRow

/// A single field row in the diff view.
/// - Compact (iPhone): stacked local → server with radio buttons on each.
/// - Regular (iPad): three-column: field | local value + radio | server value + radio.
private struct ConflictFieldRow: View {
    let field: ConflictField
    @Binding var selectedSide: ConflictSide
    let isCompact: Bool

    var body: some View {
        Group {
            if isCompact {
                compactLayout
            } else {
                regularLayout
            }
        }
        .padding(BrandSpacing.sm)
        .background(field.isDifferent ? Color.bizarreWarning.opacity(0.06) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(field.isDifferent ? Color.bizarreWarning.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(fieldA11yLabel)
        .accessibilityHint("Select local or server value for the \(field.key) field")
    }

    // MARK: Compact (iPhone)

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            HStack {
                Text(field.key)
                    .font(.brandMono(size: 12))
                    .foregroundStyle(.bizarreOnSurface)
                if field.isDifferent {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.bizarreWarning)
                        .accessibilityHidden(true)
                }
                Spacer()
            }

            sideRow(side: .local, value: field.localValue)
            sideRow(side: .server, value: field.serverValue)
        }
    }

    // MARK: Regular (iPad)

    private var regularLayout: some View {
        HStack(spacing: 0) {
            Text(field.key)
                .font(.brandMono(size: 12))
                .foregroundStyle(.bizarreOnSurface)
                .frame(maxWidth: .infinity, alignment: .leading)

            valueCell(side: .local, value: field.localValue)
            valueCell(side: .server, value: field.serverValue)
        }
    }

    private func valueCell(side: ConflictSide, value: String?) -> some View {
        HStack(spacing: BrandSpacing.xs) {
            radioButton(side: side)
            Text(value ?? "—")
                .font(.brandLabelSmall())
                .foregroundStyle(value != nil ? Color.bizarreOnSurface : Color.bizarreOnSurfaceMuted)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { selectedSide = side }
    }

    private func sideRow(side: ConflictSide, value: String?) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            radioButton(side: side)
            VStack(alignment: .leading, spacing: 2) {
                Text(side.displayName)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Text(value ?? "—")
                    .font(.brandLabelSmall())
                    .foregroundStyle(value != nil ? Color.bizarreOnSurface : Color.bizarreOnSurfaceMuted)
                    .lineLimit(3)
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture { selectedSide = side }
    }

    private func radioButton(side: ConflictSide) -> some View {
        Image(systemName: selectedSide == side ? "largecircle.fill.circle" : "circle")
            .font(.system(size: 18))
            .foregroundStyle(selectedSide == side ? Color.bizarreTeal : Color.bizarreOnSurfaceMuted)
            .accessibilityLabel(selectedSide == side ? "Selected: \(side.displayName)" : side.displayName)
            .accessibilityAddTraits(selectedSide == side ? [.isSelected] : [])
    }

    private var fieldA11yLabel: String {
        let diff = field.isDifferent ? "Values differ. " : "Values match. "
        let local = "Local: \(field.localValue ?? "empty"). "
        let server = "Server: \(field.serverValue ?? "empty"). "
        let choice = "Currently keeping \(selectedSide.displayName)."
        return "\(field.key). \(diff)\(local)\(server)\(choice)"
    }
}
