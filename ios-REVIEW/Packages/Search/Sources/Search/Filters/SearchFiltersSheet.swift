import SwiftUI
import DesignSystem

/// §18.7 — Modal sheet with date range, entity, creator/assignee, status chips.
public struct SearchFiltersSheet: View {

    @Binding var filters: SearchFilters
    @State private var localFilters: SearchFilters
    let onApply: (SearchFilters) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(filters: Binding<SearchFilters>, onApply: @escaping (SearchFilters) -> Void) {
        self._filters = filters
        self._localFilters = State(wrappedValue: filters.wrappedValue)
        self.onApply = onApply
    }

    public var body: some View {
        NavigationStack {
            Form {
                entitySection
                dateSection
                statusSection
                peopleSection
            }
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("Filters")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        withAnimation(reduceMotion ? .none : BrandMotion.snappy) {
                            localFilters = SearchFilters()
                        }
                    }
                    .foregroundStyle(.bizarreError)
                    .accessibilityLabel("Reset all filters")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply(localFilters)
                        filters = localFilters
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .accessibilityLabel("Apply filters")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Entity

    private var entitySection: some View {
        Section("Entity") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: BrandSpacing.xs) {
                    ForEach(EntityFilter.allCases, id: \.self) { filter in
                        entityChip(filter)
                    }
                }
                .padding(.vertical, BrandSpacing.xs)
            }
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    private func entityChip(_ filter: EntityFilter) -> some View {
        Button {
            withAnimation(reduceMotion ? .none : BrandMotion.snappy) {
                localFilters = SearchFilters(
                    entity: filter,
                    dateFrom: localFilters.dateFrom,
                    dateTo: localFilters.dateTo,
                    status: localFilters.status,
                    assignee: localFilters.assignee,
                    creator: localFilters.creator
                )
            }
        } label: {
            Label(filter.displayName, systemImage: filter.systemImage)
                .font(.brandLabelLarge())
                .padding(.horizontal, BrandSpacing.md)
                .padding(.vertical, BrandSpacing.xs)
                .brandGlass(localFilters.entity == filter ? .identity : .regular, interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(filter.displayName)
        .accessibilityAddTraits(localFilters.entity == filter ? .isSelected : [])
    }

    // MARK: - Date

    private var dateSection: some View {
        Section("Date Range") {
            DatePicker(
                "From",
                selection: Binding(
                    get: { localFilters.dateFrom ?? Date.distantPast },
                    set: { newVal in
                        localFilters = SearchFilters(
                            entity: localFilters.entity,
                            dateFrom: newVal,
                            dateTo: localFilters.dateTo,
                            status: localFilters.status,
                            assignee: localFilters.assignee,
                            creator: localFilters.creator
                        )
                    }
                ),
                displayedComponents: .date
            )
            .accessibilityLabel("Filter from date")

            DatePicker(
                "To",
                selection: Binding(
                    get: { localFilters.dateTo ?? Date() },
                    set: { newVal in
                        localFilters = SearchFilters(
                            entity: localFilters.entity,
                            dateFrom: localFilters.dateFrom,
                            dateTo: newVal,
                            status: localFilters.status,
                            assignee: localFilters.assignee,
                            creator: localFilters.creator
                        )
                    }
                ),
                displayedComponents: .date
            )
            .accessibilityLabel("Filter to date")

            Button("Clear dates") {
                localFilters = SearchFilters(
                    entity: localFilters.entity,
                    dateFrom: nil,
                    dateTo: nil,
                    status: localFilters.status,
                    assignee: localFilters.assignee,
                    creator: localFilters.creator
                )
            }
            .foregroundStyle(.bizarreOnSurfaceMuted)
            .accessibilityLabel("Clear date range")
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    // MARK: - Status

    private static let statusOptions = ["intake", "in_progress", "ready", "completed", "archived"]

    private var statusSection: some View {
        Section("Status") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: BrandSpacing.xs) {
                    ForEach(Self.statusOptions, id: \.self) { status in
                        statusChip(status)
                    }
                }
                .padding(.vertical, BrandSpacing.xs)
            }
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    private func statusChip(_ status: String) -> some View {
        Button {
            let newStatus = localFilters.status == status ? nil : status
            localFilters = SearchFilters(
                entity: localFilters.entity,
                dateFrom: localFilters.dateFrom,
                dateTo: localFilters.dateTo,
                status: newStatus,
                assignee: localFilters.assignee,
                creator: localFilters.creator
            )
        } label: {
            Text(status.replacingOccurrences(of: "_", with: " ").capitalized)
                .font(.brandLabelLarge())
                .padding(.horizontal, BrandSpacing.md)
                .padding(.vertical, BrandSpacing.xs)
                .brandGlass(localFilters.status == status ? .identity : .regular, interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(status)
        .accessibilityAddTraits(localFilters.status == status ? .isSelected : [])
    }

    // MARK: - People

    private var peopleSection: some View {
        Section("People") {
            TextField("Assignee", text: Binding(
                get: { localFilters.assignee ?? "" },
                set: { val in
                    localFilters = SearchFilters(
                        entity: localFilters.entity,
                        dateFrom: localFilters.dateFrom,
                        dateTo: localFilters.dateTo,
                        status: localFilters.status,
                        assignee: val.isEmpty ? nil : val,
                        creator: localFilters.creator
                    )
                }
            ))
            .accessibilityLabel("Assignee filter")

            TextField("Creator", text: Binding(
                get: { localFilters.creator ?? "" },
                set: { val in
                    localFilters = SearchFilters(
                        entity: localFilters.entity,
                        dateFrom: localFilters.dateFrom,
                        dateTo: localFilters.dateTo,
                        status: localFilters.status,
                        assignee: localFilters.assignee,
                        creator: val.isEmpty ? nil : val
                    )
                }
            ))
            .accessibilityLabel("Creator filter")
        }
        .listRowBackground(Color.bizarreSurface1)
    }
}
