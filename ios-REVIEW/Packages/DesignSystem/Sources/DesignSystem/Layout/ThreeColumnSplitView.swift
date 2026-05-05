import SwiftUI

// §22.1 — 3-column NavigationSplitView wiring example.
//
// Provides a ready-to-use scaffold that wires the three columns required by
// Tickets / Customers / Invoices / Inventory / SMS / Estimates / Appointments /
// Leads:
//
//   • Sidebar  — domain chooser (section tabs / rail items).
//   • List     — per-domain list of records.
//   • Detail   — full record detail with optional inspector pane.
//
// Usage:
//   ThreeColumnSplitView(
//       sidebar: { DomainChooser() },
//       list:    { domain in RecordList(domain: domain) },
//       detail:  { record in RecordDetail(record: record) }
//   )
//
// On compact-width devices the split view collapses to a standard push
// navigation stack automatically (SwiftUI default behaviour).

// MARK: - Domain selection model

/// A domain identifier used to drive the list column.
///
/// Conform your app-level section enum to this protocol so
/// `ThreeColumnSplitView` can select the correct list on sidebar tap.
public protocol SplitViewDomain: Hashable, Sendable {}

// MARK: - ThreeColumnSplitView

/// A 3-column `NavigationSplitView` scaffold for iPad (§22.1).
///
/// - Generic parameters:
///   - `Domain`: The sidebar selection type (must conform to `SplitViewDomain`).
///   - `Record`: The list-row selection type (must be `Hashable`).
///   - `Sidebar`: View shown in the leading sidebar column.
///   - `ListContent`: View shown in the middle list column.
///   - `DetailContent`: View shown in the trailing detail column.
public struct ThreeColumnSplitView<
    Domain: SplitViewDomain,
    Record: Hashable & Sendable,
    Sidebar: View,
    ListContent: View,
    DetailContent: View
>: View {

    // MARK: - State

    @State private var selectedDomain: Domain?
    @State private var selectedRecord: Record?

    // MARK: - Stored properties

    private let sidebar: () -> Sidebar
    private let list: (Domain?) -> ListContent
    private let detail: (Record?) -> DetailContent

    // MARK: - Init

    /// Creates a 3-column split view.
    ///
    /// - Parameters:
    ///   - sidebar: View builder for the leading sidebar column.  Typically a
    ///     list of domain icons / labels (Tickets, Customers, …).
    ///   - list: View builder for the centre list column, receiving the
    ///     currently selected domain.
    ///   - detail: View builder for the trailing detail column, receiving the
    ///     currently selected record (or `nil` when nothing is selected).
    public init(
        @ViewBuilder sidebar: @escaping () -> Sidebar,
        @ViewBuilder list: @escaping (Domain?) -> ListContent,
        @ViewBuilder detail: @escaping (Record?) -> DetailContent
    ) {
        self.sidebar = sidebar
        self.list = list
        self.detail = detail
    }

    // MARK: - Body

    public var body: some View {
        NavigationSplitView(
            columnVisibility: .constant(.all)
        ) {
            // ── Sidebar column ──────────────────────────────────────────────
            sidebar()
                .navigationSplitViewColumnWidth(
                    min: ThreeColumnSplitConstants.sidebarMinWidth,
                    ideal: ThreeColumnSplitConstants.sidebarIdealWidth,
                    max: ThreeColumnSplitConstants.sidebarMaxWidth
                )
        } content: {
            // ── List column ─────────────────────────────────────────────────
            list(selectedDomain)
                .navigationSplitViewColumnWidth(
                    min: ThreeColumnSplitConstants.listMinWidth,
                    ideal: ThreeColumnSplitConstants.listIdealWidth,
                    max: ThreeColumnSplitConstants.listMaxWidth
                )
        } detail: {
            // ── Detail column ───────────────────────────────────────────────
            detail(selectedRecord)
        }
        .navigationSplitViewStyle(.balanced)
    }
}

// MARK: - Constants

/// Layout constants for `ThreeColumnSplitView` (§22.1).
public enum ThreeColumnSplitConstants {
    /// Sidebar: icon-rail minimum (56 pt).
    public static let sidebarMinWidth: CGFloat = 56
    /// Sidebar: expanded label+icon ideal (260 pt).
    public static let sidebarIdealWidth: CGFloat = 260
    /// Sidebar: never wider than this (320 pt).
    public static let sidebarMaxWidth: CGFloat = 320

    /// List column minimum (280 pt).
    public static let listMinWidth: CGFloat = 280
    /// List column ideal (340 pt).
    public static let listIdealWidth: CGFloat = 340
    /// List column maximum (420 pt).
    public static let listMaxWidth: CGFloat = 420

    /// Detail pane caps at 720 pt on 13" landscape (§22.1 max-content-width).
    public static let detailMaxWidth: CGFloat = 720
}

// MARK: - Detail content-width cap modifier

/// Caps a detail pane's content to `ThreeColumnSplitConstants.detailMaxWidth`
/// with symmetric padding on wider screens (§22.1).
///
/// ```swift
/// RecordDetailView()
///     .detailContentCapped()
/// ```
public struct DetailContentCappedModifier: ViewModifier {
    public init() {}

    public func body(content: Content) -> some View {
        content
            .frame(maxWidth: ThreeColumnSplitConstants.detailMaxWidth)
            .frame(maxWidth: .infinity)   // centre within the column
    }
}

public extension View {
    /// Caps this view's width to 720 pt and centres it — required for all
    /// detail panes on 13" iPad landscape (§22.1).
    func detailContentCapped() -> some View {
        modifier(DetailContentCappedModifier())
    }
}
