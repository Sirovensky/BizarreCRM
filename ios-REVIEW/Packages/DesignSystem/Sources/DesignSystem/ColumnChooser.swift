import SwiftUI

// §22.5 — Column chooser: reorder / hide columns; persisted.
//
// Companion to `BrandSortableTable`.  Owns the user's column-visibility +
// column-order preferences and persists them to `UserDefaults` keyed by a
// caller-supplied table identity (e.g. "reports.sales", "inventory.dump").
// Render the chooser UI by attaching `.brandColumnChooser(state:)` to a
// table toolbar item — a button with a checklist popover appears that
// toggles columns and supports drag-to-reorder.
//
// Usage:
//   @StateObject var cols = ColumnChooserState(
//       storageKey: "reports.sales",
//       columns: [.init(id: "date",   title: "Date"),
//                 .init(id: "amount", title: "Amount"),
//                 .init(id: "tech",   title: "Tech")]
//   )
//
//   BrandSortableTable(rows: rows, initialOrder: [...]) {
//       ForEach(cols.visibleOrdered) { c in
//           if c.id == "date"   { TableColumn("Date", value: \.date)   { … } }
//           if c.id == "amount" { TableColumn("Amount", value: \.amount) { … } }
//           …
//       }
//   }
//   .toolbar { ToolbarItem { ColumnChooserButton(state: cols) } }

// MARK: - Model

/// Single column descriptor used by `ColumnChooserState`.
public struct ColumnDescriptor: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public var title: String
    public var isVisible: Bool

    public init(id: String, title: String, isVisible: Bool = true) {
        self.id = id
        self.title = title
        self.isVisible = isVisible
    }
}

// MARK: - State store

/// `@StateObject`-friendly store that persists column visibility + order
/// to `UserDefaults` under `storageKey`.
@MainActor
public final class ColumnChooserState: ObservableObject {

    public let storageKey: String
    private let defaults: UserDefaults

    @Published public private(set) var columns: [ColumnDescriptor]

    /// Columns in user-chosen order with hidden ones filtered out.
    /// Use this when iterating `TableColumn`s.
    public var visibleOrdered: [ColumnDescriptor] {
        columns.filter { $0.isVisible }
    }

    public init(
        storageKey: String,
        columns: [ColumnDescriptor],
        defaults: UserDefaults = .standard
    ) {
        self.storageKey = storageKey
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let stored = try? JSONDecoder().decode([ColumnDescriptor].self, from: data) {
            // Merge stored visibility/order with current schema — drop
            // unknown ids, append any new columns at the end.
            var merged: [ColumnDescriptor] = stored.compactMap { s in
                columns.first { $0.id == s.id }.map {
                    var c = $0
                    c.isVisible = s.isVisible
                    return c
                }
            }
            for col in columns where !merged.contains(where: { $0.id == col.id }) {
                merged.append(col)
            }
            self.columns = merged
        } else {
            self.columns = columns
        }
    }

    public func toggle(_ id: String) {
        guard let idx = columns.firstIndex(where: { $0.id == id }) else { return }
        columns[idx].isVisible.toggle()
        persist()
    }

    public func move(from source: IndexSet, to destination: Int) {
        columns.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(columns) {
            defaults.set(data, forKey: storageKey)
        }
    }
}

// MARK: - UI: chooser button

/// Toolbar button that surfaces the column chooser popover.
public struct ColumnChooserButton: View {

    @ObservedObject private var state: ColumnChooserState
    @State private var showing = false

    public init(state: ColumnChooserState) {
        self.state = state
    }

    public var body: some View {
        Button {
            showing = true
        } label: {
            Image(systemName: "slider.horizontal.3")
        }
        .accessibilityLabel("Choose columns")
        .popover(isPresented: $showing) {
            List {
                ForEach(state.columns) { col in
                    Toggle(col.title, isOn: Binding(
                        get: { col.isVisible },
                        set: { _ in state.toggle(col.id) }
                    ))
                }
                .onMove { state.move(from: $0, to: $1) }
            }
            .environment(\.editMode, .constant(.active))
            .frame(minWidth: 240, minHeight: 280)
        }
    }
}
