import SwiftUI
import DesignSystem

// MARK: - SavedReportListSheet

/// Sheet that lets the user browse and load previously saved report views.
///
/// Presents the full list of `SavedReportView` values from a `SavedReportStore`.
/// When the user taps a row, `onSelect` is called with the chosen view and
/// the sheet dismisses. Swipe-to-delete removes a view from the store.
///
/// Liquid Glass: sheet header only. List rows are content — no glass.
public struct SavedReportListSheet: View {

    // MARK: Dependencies

    private let store: SavedReportStore
    private let onSelect: (SavedReportView) -> Void

    // MARK: Local state

    @State private var views: [SavedReportView] = []
    @State private var isLoading = true
    @State private var deleteError: String?
    @Environment(\.dismiss) private var dismiss

    // MARK: Init

    public init(store: SavedReportStore, onSelect: @escaping (SavedReportView) -> Void) {
        self.store = store
        self.onSelect = onSelect
    }

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle("Saved Views")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .brandGlass(.clear, in: Capsule())
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task { await reload() }
        .alert("Delete Error", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "")
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
                .tint(.bizarreOrange)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Loading saved views")
        } else if views.isEmpty {
            emptyState
        } else {
            listBody
        }
    }

    private var emptyState: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "bookmark.slash")
                .font(.system(size: 44))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("No Saved Views")
                .font(.brandTitleLarge())
                .foregroundStyle(.bizarreOnSurface)
            Text("Use \"Save Current View\" from the Reports toolbar to bookmark a set of filters.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var listBody: some View {
        List {
            ForEach(views) { view in
                SavedReportRow(view: view)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onSelect(view)
                        dismiss()
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        "\(view.name), \(view.reportKind.displayName), \(view.dateRange.displayLabel), saved \(view.formattedCreatedDate)"
                    )
                    .accessibilityHint("Double tap to load this view")
            }
            .onDelete { indexSet in
                Task { await deleteViews(at: indexSet) }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Actions

    private func reload() async {
        isLoading = true
        views = await store.all
        isLoading = false
    }

    private func deleteViews(at offsets: IndexSet) async {
        let toDelete = offsets.map { views[$0] }
        for view in toDelete {
            await store.delete(id: view.id)
        }
        views = await store.all
    }
}

// MARK: - SavedReportRow

private struct SavedReportRow: View {
    let view: SavedReportView

    var body: some View {
        HStack(spacing: BrandSpacing.base) {
            Image(systemName: view.reportKind.systemImageName)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.bizarreOrange)
                .frame(width: DesignTokens.Touch.minTargetSide,
                       height: DesignTokens.Touch.minTargetSide)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(view.name)
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)

                HStack(spacing: BrandSpacing.sm) {
                    Text(view.reportKind.displayName)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)

                    Text("·")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityHidden(true)

                    Text(view.dateRange.displayLabel)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }

            Spacer()

            Text(view.formattedCreatedDate)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .padding(.vertical, BrandSpacing.xs)
    }
}
