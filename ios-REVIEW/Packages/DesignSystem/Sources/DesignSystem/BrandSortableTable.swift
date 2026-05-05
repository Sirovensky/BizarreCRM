import SwiftUI

// §22.5 — `Table` (sortable columns) on Reports, Inventory dumps, Audit Logs.
//
// SwiftUI's `Table` ships with native column sorting via `KeyPathComparator`,
// but every call site needs the same boilerplate: a `[KeyPathComparator]`
// state, the `sortOrder:` binding, and post-sort dataset re-derivation.
// `BrandSortableTable` collapses that into a single view that takes a raw
// data array, an initial sort, and the column builder.  The view sorts the
// data internally and keeps the SwiftUI sort affordance (the column-header
// chevron + click-to-cycle) wired up automatically.
//
// Usage:
//   BrandSortableTable(
//       rows: report.rows,
//       initialOrder: [KeyPathComparator(\Row.date, order: .reverse)]
//   ) {
//       TableColumn("Date",   value: \.date)   { Text($0.date.formatted()) }
//       TableColumn("Amount", value: \.amount) { Text($0.amount.formatted(.currency(code: "USD"))) }
//       TableColumn("Tech",   value: \.tech)   { Text($0.tech) }
//   }
//
// On compact-width devices `Table` collapses to its first column; this
// matches Apple's behaviour and keeps the API one-line on iPad + Mac.

@available(iOS 16.0, *)
public struct BrandSortableTable<
    Row: Identifiable,
    Columns: TableColumnContent
>: View where Columns.TableRowValue == Row {

    // MARK: - Stored properties

    private let rows: [Row]
    @State private var sortOrder: [KeyPathComparator<Row>]
    private let columns: () -> Columns

    // MARK: - Init

    /// - Parameters:
    ///   - rows: The dataset to display. Re-sorted in place when the user
    ///     clicks a column header.
    ///   - initialOrder: The starting sort order. Pass at least one
    ///     `KeyPathComparator` so the table opens already sorted.
    ///   - columns: Column builder (use SwiftUI's `TableColumn`).
    public init(
        rows: [Row],
        initialOrder: [KeyPathComparator<Row>],
        @TableColumnBuilder<Row, KeyPathComparator<Row>> columns: @escaping () -> Columns
    ) {
        self.rows = rows
        self._sortOrder = State(initialValue: initialOrder)
        self.columns = columns
    }

    // MARK: - Body

    public var body: some View {
        let sorted = rows.sorted(using: sortOrder)
        Table(sorted, sortOrder: $sortOrder, columns: columns)
    }
}
