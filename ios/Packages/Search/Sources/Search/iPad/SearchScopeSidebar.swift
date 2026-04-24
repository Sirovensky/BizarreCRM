import SwiftUI
import DesignSystem

/// §22.2 — Left-column scope sidebar for the iPad 3-column search layout.
///
/// Shows All + 5 entity toggles (Customers / Tickets / Inventory / Invoices / Notes).
/// Each row carries a Liquid Glass capsule background, an SF Symbol icon,
/// a display-name label, and an optional result-count badge.
/// The active scope row uses `.identity` glass; inactive rows use `.regular`.
public struct SearchScopeSidebar: View {

    // MARK: - Inputs

    /// Currently active scope (two-way binding owned by the parent view).
    @Binding public var selectedScope: SearchScope

    /// Per-scope result counts. Pass `.zero` when no search is running.
    public var counts: SearchScopeCounts

    /// Called when the user taps a scope row.
    public var onScopeSelected: ((SearchScope) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Init

    public init(
        selectedScope: Binding<SearchScope>,
        counts: SearchScopeCounts = .zero,
        onScopeSelected: ((SearchScope) -> Void)? = nil
    ) {
        _selectedScope = selectedScope
        self.counts = counts
        self.onScopeSelected = onScopeSelected
    }

    // MARK: - Body

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.top, BrandSpacing.base)
                    .padding(.bottom, BrandSpacing.sm)

                BrandGlassContainer(spacing: BrandSpacing.xs) {
                    VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                        ForEach(SearchScope.allCases, id: \.self) { scope in
                            scopeRow(scope)
                        }
                    }
                    .padding(.horizontal, BrandSpacing.base)
                }

                Spacer()
            }
        }
        .frame(minWidth: 220, idealWidth: 260, maxWidth: 300)
    }

    // MARK: - Section header

    private var sectionHeader: some View {
        Text("Scope")
            .font(.brandLabelSmall())
            .foregroundStyle(.bizarreOnSurfaceMuted)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Scope row

    private func scopeRow(_ scope: SearchScope) -> some View {
        let isSelected = selectedScope == scope
        let count = counts.count(for: scope)

        return Button {
            withAnimation(reduceMotion ? .none : BrandMotion.snappy) {
                selectedScope = scope
            }
            onScopeSelected?(scope)
        } label: {
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: scope.systemImage)
                    .frame(width: 22)
                    .foregroundStyle(isSelected ? .bizarreOrange : .bizarreOnSurface)
                    .accessibilityHidden(true)

                Text(scope.displayName)
                    .font(.brandLabelLarge())
                    .foregroundStyle(isSelected ? .bizarreOnSurface : .bizarreOnSurface)

                Spacer(minLength: 0)

                if count > 0 {
                    countBadge(count, isSelected: isSelected)
                }

                if let digit = scope.shortcutDigit {
                    shortcutHint(digit, isSelected: isSelected)
                }
            }
            .padding(.horizontal, BrandSpacing.md)
            .padding(.vertical, BrandSpacing.sm)
            .brandGlass(isSelected ? .identity : .regular, in: RoundedRectangle(cornerRadius: 12), interactive: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .brandHover()
        .accessibilityLabel(accessibilityLabel(for: scope, count: count))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Count badge

    private func countBadge(_ count: Int, isSelected: Bool) -> some View {
        Text("\(min(count, 99))\(count > 99 ? "+" : "")")
            .font(.brandLabelSmall().monospacedDigit())
            .foregroundStyle(isSelected ? .white : .bizarreOrange)
            .padding(.horizontal, BrandSpacing.xs)
            .padding(.vertical, BrandSpacing.xxs)
            .background(
                Capsule()
                    .fill(isSelected
                          ? Color.bizarreOrange
                          : Color.bizarreOrange.opacity(0.15))
            )
    }

    // MARK: - Keyboard shortcut hint

    private func shortcutHint(_ digit: Int, isSelected: Bool) -> some View {
        Text("⌘\(digit)")
            .font(.brandMono(size: 11))
            .foregroundStyle(.bizarreOnSurfaceMuted)
            .opacity(0.6)
            .accessibilityHidden(true)
    }

    // MARK: - Accessibility

    private func accessibilityLabel(for scope: SearchScope, count: Int) -> String {
        let countSuffix = count > 0 ? ", \(count) results" : ""
        return "\(scope.displayName)\(countSuffix)"
    }
}

// MARK: - SearchScopeCounts

/// Per-scope result counts displayed as badges in the sidebar.
public struct SearchScopeCounts: Sendable, Equatable {
    public var all: Int
    public var customers: Int
    public var tickets: Int
    public var inventory: Int
    public var invoices: Int
    public var notes: Int

    public static let zero = SearchScopeCounts(
        all: 0, customers: 0, tickets: 0, inventory: 0, invoices: 0, notes: 0
    )

    public init(
        all: Int = 0,
        customers: Int = 0,
        tickets: Int = 0,
        inventory: Int = 0,
        invoices: Int = 0,
        notes: Int = 0
    ) {
        self.all = all
        self.customers = customers
        self.tickets = tickets
        self.inventory = inventory
        self.invoices = invoices
        self.notes = notes
    }

    public func count(for scope: SearchScope) -> Int {
        switch scope {
        case .all:       return all
        case .customers: return customers
        case .tickets:   return tickets
        case .inventory: return inventory
        case .invoices:  return invoices
        case .notes:     return notes
        }
    }

    /// Build counts from a flat array of `SearchHit`.
    public static func from(hits: [SearchHit]) -> SearchScopeCounts {
        var c = SearchScopeCounts()
        for hit in hits {
            switch hit.entity {
            case "customers": c.customers += 1
            case "tickets":   c.tickets += 1
            case "inventory": c.inventory += 1
            case "invoices":  c.invoices += 1
            case "notes":     c.notes += 1
            default: break
            }
        }
        c.all = c.customers + c.tickets + c.inventory + c.invoices + c.notes
        return c
    }

    /// Merge with `ScopeCounts` (FTS + remote), taking the max per entity.
    public func merged(with fts: ScopeCounts) -> SearchScopeCounts {
        let mergedCustomers = max(customers, fts.customers)
        let mergedTickets   = max(tickets, fts.tickets)
        let mergedInventory = max(inventory, fts.inventory)
        let mergedInvoices  = max(invoices, fts.invoices)
        return SearchScopeCounts(
            all: mergedCustomers + mergedTickets + mergedInventory + mergedInvoices + notes,
            customers: mergedCustomers,
            tickets: mergedTickets,
            inventory: mergedInventory,
            invoices: mergedInvoices,
            notes: notes
        )
    }
}
