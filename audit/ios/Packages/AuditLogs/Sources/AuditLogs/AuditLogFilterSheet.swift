import SwiftUI
import Core
import DesignSystem

/// Filter sheet for the Audit Logs list (§50.2).
/// Presented as a bottom sheet on iPhone, side panel on iPad (caller decides).
public struct AuditLogFilterSheet: View {

    @Binding var filters: AuditLogFilters
    @Binding var selectedRange: AuditDateRange?

    private let onApply: (AuditLogFilters) -> Void
    private let onClear: () -> Void
    @Environment(\.dismiss) private var dismiss

    /// Mutable local copy that is committed on "Apply".
    @State private var draft: AuditLogFilters

    // Common action strings presented for multi-select.
    private let knownActions: [String] = [
        "ticket.create", "ticket.update", "ticket.delete",
        "customer.create", "customer.update", "customer.delete",
        "invoice.create", "invoice.update",
        "employee.create", "employee.update",
        "role.update", "user.login", "user.logout"
    ]

    private let entityTypes: [String] = [
        "All", "ticket", "customer", "invoice", "employee", "inventory"
    ]

    public init(
        filters: Binding<AuditLogFilters>,
        selectedRange: Binding<AuditDateRange?>,
        onApply: @escaping (AuditLogFilters) -> Void,
        onClear: @escaping () -> Void
    ) {
        _filters = filters
        _selectedRange = selectedRange
        self.onApply = onApply
        self.onClear = onClear
        _draft = State(wrappedValue: filters.wrappedValue)
    }

    public var body: some View {
        NavigationStack {
            Form {
                quickRangeSection
                searchSection
                entitySection
                actionSection
                dateRangeSection
            }
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase)
            .navigationTitle("Filter Logs")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if draft.isActive {
                    Button("Clear All Filters", role: .destructive) {
                        draft = .empty
                        onClear()
                        dismiss()
                    }
                    .font(.brandBodyMedium())
                    .padding()
                    .frame(maxWidth: .infinity)
                    .brandGlass(.regular, tint: .bizarreError)
                    .padding()
                }
            }
        }
    }

    // MARK: Sections

    private var quickRangeSection: some View {
        Section("Quick Range") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    ForEach(AuditDateRange.allCases, id: \.self) { range in
                        Button(range.rawValue) {
                            selectedRange = range
                            if let interval = range.dateInterval() {
                                draft = AuditLogFilters(
                                    actorId:    draft.actorId,
                                    actions:    draft.actions,
                                    entityType: draft.entityType,
                                    since:      interval.since,
                                    until:      interval.until,
                                    query:      draft.query
                                )
                            }
                        }
                        .buttonStyle(.brandGlass)
                        .tint(selectedRange == range ? .bizarreOrange : .secondary)
                        .accessibilityLabel("\(range.rawValue) filter")
                        .accessibilityAddTraits(selectedRange == range ? .isSelected : [])
                    }
                }
                .padding(.vertical, DesignTokens.Spacing.xs)
            }
            .listRowInsets(.init(top: 4, leading: 0, bottom: 4, trailing: 0))
            .listRowBackground(Color.clear)
        }
    }

    private var searchSection: some View {
        Section("Search") {
            TextField("Search log content…", text: $draft.query)
                #if canImport(UIKit)
                .textInputAutocapitalization(.never)
                #endif
                .disableAutocorrection(true)
                .accessibilityIdentifier("auditlog.filter.search")
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    private var entitySection: some View {
        Section("Entity Type") {
            Picker("Entity", selection: Binding(
                get: { draft.entityType ?? "All" },
                set: { draft.entityType = $0 == "All" ? nil : $0 }
            )) {
                ForEach(entityTypes, id: \.self) { t in
                    Text(t.capitalized).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("auditlog.filter.entity")
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    private var actionSection: some View {
        Section("Actions") {
            ForEach(knownActions, id: \.self) { action in
                Toggle(action, isOn: Binding(
                    get: { draft.actions.contains(action) },
                    set: { on in
                        if on {
                            draft.actions.append(action)
                        } else {
                            draft.actions.removeAll { $0 == action }
                        }
                    }
                ))
                .font(.brandMono(size: 13))
                .tint(.bizarreOrange)
            }
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    private var dateRangeSection: some View {
        Section("Custom Date Range") {
            DatePicker(
                "From",
                selection: Binding(
                    get: { draft.since ?? Date() },
                    set: { draft.since = $0; selectedRange = .custom }
                ),
                displayedComponents: .date
            )
            DatePicker(
                "To",
                selection: Binding(
                    get: { draft.until ?? Date() },
                    set: { draft.until = $0; selectedRange = .custom }
                ),
                displayedComponents: .date
            )
        }
        .listRowBackground(Color.bizarreSurface1)
    }
}
