import SwiftUI
import DesignSystem

// MARK: - SaveCurrentReportSheet

/// "Save As" dialog that captures the current report state as a `SavedReportView`.
///
/// The caller provides the current `reportKind`, `dateRange`, and optional
/// `filters`. The user fills in a name and taps Save.
///
/// On success, `onSaved` is called with the new `SavedReportView` and the
/// sheet dismisses. On duplicate-name or empty-name errors, an inline error
/// message is shown without dismissing.
///
/// Liquid Glass: sheet header. Input area is standard surface content.
public struct SaveCurrentReportSheet: View {

    // MARK: Dependencies

    private let store: SavedReportStore
    private let reportKind: ReportKind
    private let dateRange: DateRangePreset
    private let filters: SavedReportFilters
    private let onSaved: (SavedReportView) -> Void

    // MARK: Local state

    @State private var name: String = ""
    @State private var isSaving = false
    @State private var validationError: String?
    @FocusState private var nameFieldFocused: Bool
    @Environment(\.dismiss) private var dismiss

    // MARK: Init

    public init(
        store: SavedReportStore,
        reportKind: ReportKind,
        dateRange: DateRangePreset,
        filters: SavedReportFilters = .empty,
        onSaved: @escaping (SavedReportView) -> Void
    ) {
        self.store = store
        self.reportKind = reportKind
        self.dateRange = dateRange
        self.filters = filters
        self.onSaved = onSaved
    }

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                formBody
            }
            .navigationTitle("Save View")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .brandGlass(.clear, in: Capsule())
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await saveView() }
                    }
                    .buttonStyle(.brandGlassProminent)
                    .tint(.bizarreOrange)
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Save current report view")
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear { nameFieldFocused = true }
    }

    // MARK: - Form

    private var formBody: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.lg) {
            summaryCard
                .padding(.horizontal, BrandSpacing.base)
                .padding(.top, BrandSpacing.lg)

            nameField
                .padding(.horizontal, BrandSpacing.base)

            if let error = validationError {
                Text(error)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreError)
                    .padding(.horizontal, BrandSpacing.base)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .accessibilityLabel("Error: \(error)")
            }

            Spacer()
        }
    }

    // MARK: Summary card

    private var summaryCard: some View {
        HStack(spacing: BrandSpacing.base) {
            Image(systemName: reportKind.systemImageName)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.bizarreOrange)
                .frame(
                    width: DesignTokens.Touch.minTargetSide,
                    height: DesignTokens.Touch.minTargetSide
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(reportKind.displayName)
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
                Text(dateRange.displayLabel)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .padding(BrandSpacing.base)
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Saving \(reportKind.displayName) report, \(dateRange.displayLabel) range")
    }

    // MARK: Name field

    private var nameField: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text("View Name")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)

            TextField("e.g. Q1 Revenue", text: $name)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .focused($nameFieldFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .onSubmit { Task { await saveView() } }
                .onChange(of: name) { _, _ in validationError = nil }
                .padding(BrandSpacing.base)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                        .fill(Color.bizarreSurface1)
                )
                .accessibilityLabel("View name text field")
        }
    }

    // MARK: - Save action

    private func saveView() async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            withAnimation { validationError = "Please enter a name for this view." }
            return
        }

        isSaving = true
        defer { isSaving = false }

        let newView = SavedReportView(
            name: trimmed,
            reportKind: reportKind,
            dateRange: dateRange,
            filters: filters
        )

        do {
            try await store.save(newView)
            onSaved(newView)
            dismiss()
        } catch SavedReportStoreError.duplicateName(let dup) {
            withAnimation {
                validationError = "A view named \"\(dup)\" already exists. Choose a different name."
            }
        } catch SavedReportStoreError.emptyName {
            withAnimation { validationError = "Please enter a name for this view." }
        } catch {
            withAnimation { validationError = error.localizedDescription }
        }
    }
}
