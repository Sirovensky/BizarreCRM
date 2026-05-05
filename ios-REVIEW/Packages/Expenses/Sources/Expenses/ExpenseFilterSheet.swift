import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - ExpenseFilterSheet

/// A `.presentationDetents([.medium])` sheet that lets the user pick
/// category / date-range / approval-status filters applied to the
/// `GET /expenses` request via `ExpenseListFilter`.
///
/// Bound to `$vm.filter` via a Binding; changes commit when "Apply" is tapped.
/// The parent view is responsible for dismissing and reloading.
public struct ExpenseFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding public var filter: ExpenseListFilter

    // Local draft — only committed on "Apply"
    @State private var draftCategory: String
    @State private var draftFromDate: Date?
    @State private var draftToDate: Date?
    @State private var draftStatus: String
    /// §11.1 reimbursable flag filter (nil = any, true = reimbursable only, false = non-reimbursable)
    @State private var draftReimbursable: Bool?
    @State private var showFromPicker: Bool = false
    @State private var showToPicker: Bool = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    public init(filter: Binding<ExpenseListFilter>) {
        _filter = filter
        let f = filter.wrappedValue
        _draftCategory    = State(initialValue: f.category ?? "")
        _draftStatus      = State(initialValue: f.status ?? "")
        _draftFromDate    = State(initialValue: f.fromDate.flatMap { Self.dateFormatter.date(from: $0) })
        _draftToDate      = State(initialValue: f.toDate.flatMap   { Self.dateFormatter.date(from: $0) })
        _draftReimbursable = State(initialValue: f.isReimbursable)
    }

    public var body: some View {
        NavigationStack {
            Form {
                categorySection
                statusSection
                reimbursableSection
                dateRangeSection
            }
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("Filter Expenses")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("expenses.filter.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        commitDraft()
                        dismiss()
                    }
                    .accessibilityIdentifier("expenses.filter.apply")
                }
                #if os(iOS)
                ToolbarItem(placement: .bottomBar) {
                    Button("Clear All") {
                        clearDraft()
                        commitDraft()
                        dismiss()
                    }
                    .foregroundStyle(.bizarreError)
                    .accessibilityLabel("Clear all expense filters")
                    .accessibilityIdentifier("expenses.filter.clear")
                }
                #endif
            }
        }
    }

    // MARK: - Category section

    private var categorySection: some View {
        Section("Category") {
            Picker("Category", selection: $draftCategory) {
                Text("Any").tag("")
                    .accessibilityLabel("No category filter")
                ForEach(ExpenseCategory.allCases, id: \.rawValue) { cat in
                    Text(cat.rawValue).tag(cat.rawValue)
                }
            }
            .accessibilityLabel("Filter by expense category")
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    // MARK: - Status section

    private var statusSection: some View {
        Section("Approval Status") {
            Picker("Status", selection: $draftStatus) {
                Text("Any").tag("")
                    .accessibilityLabel("No status filter")
                Text("Pending").tag("pending")
                Text("Approved").tag("approved")
                Text("Denied").tag("denied")
            }
            .accessibilityLabel("Filter by approval status")
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    // MARK: - §11.1 Reimbursable flag section

    private var reimbursableSection: some View {
        Section("Reimbursable") {
            Picker("Reimbursable", selection: Binding(
                get: {
                    switch draftReimbursable {
                    case .none:  return 0
                    case .some(true):  return 1
                    case .some(false): return 2
                    }
                },
                set: { v in
                    switch v {
                    case 1:  draftReimbursable = true
                    case 2:  draftReimbursable = false
                    default: draftReimbursable = nil
                    }
                }
            )) {
                Text("Any").tag(0).accessibilityLabel("No reimbursable filter")
                Text("Reimbursable only").tag(1)
                Text("Non-reimbursable only").tag(2)
            }
            .accessibilityLabel("Filter by reimbursable status")
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    // MARK: - Date range section

    private var dateRangeSection: some View {
        Section("Date Range") {
            DatePickerRow(
                label: "From",
                date: $draftFromDate,
                showPicker: $showFromPicker,
                maxDate: draftToDate
            )
            DatePickerRow(
                label: "To",
                date: $draftToDate,
                showPicker: $showToPicker,
                minDate: draftFromDate
            )
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    // MARK: - Helpers

    private func commitDraft() {
        filter = ExpenseListFilter(
            category: draftCategory.isEmpty ? nil : draftCategory,
            fromDate: draftFromDate.map { Self.dateFormatter.string(from: $0) },
            toDate: draftToDate.map { Self.dateFormatter.string(from: $0) },
            status: draftStatus.isEmpty ? nil : draftStatus,
            isReimbursable: draftReimbursable
        )
    }

    private func clearDraft() {
        draftCategory = ""
        draftStatus = ""
        draftFromDate = nil
        draftToDate = nil
        draftReimbursable = nil
    }
}

// MARK: - DatePickerRow helper

private struct DatePickerRow: View {
    let label: String
    @Binding var date: Date?
    @Binding var showPicker: Bool
    var minDate: Date? = nil
    var maxDate: Date? = nil

    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
                if let d = date {
                    Button(Self.displayFormatter.string(from: d)) {
                        showPicker.toggle()
                    }
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityLabel("\(label) date: \(Self.displayFormatter.string(from: d)). Tap to change.")
                    Button {
                        date = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear \(label.lowercased()) date")
                } else {
                    Button("Select") {
                        showPicker = true
                    }
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityLabel("Select \(label.lowercased()) date")
                }
            }
            .padding(.vertical, BrandSpacing.xs)
            if showPicker {
                DatePicker(
                    "",
                    selection: Binding(
                        get: { date ?? Date() },
                        set: { date = $0 }
                    ),
                    in: dateRange,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .tint(.bizarreOrange)
                .labelsHidden()
                .accessibilityLabel("\(label) date picker")
            }
        }
    }

    private var dateRange: ClosedRange<Date> {
        let min = minDate ?? Date.distantPast
        let max = maxDate ?? Date.distantFuture
        return min <= max ? min...max : Date.distantPast...Date.distantFuture
    }
}
