import Foundation
import Observation

// MARK: - CommandPaletteViewModel

@Observable
@MainActor
public final class CommandPaletteViewModel {

    // MARK: - Published state

    /// Current search query typed by the user.
    public var query: String = "" {
        didSet { refreshResults() }
    }

    /// Filtered + ranked actions for the current query.
    public private(set) var filteredResults: [CommandAction] = []

    /// Currently highlighted row index, or `nil` if nothing selected.
    public private(set) var selectedIndex: Int? = nil

    /// Set to `true` when the palette should be dismissed.
    public private(set) var isDismissed: Bool = false

    /// Parsed entity suggestion from free-text input (ticket #, phone, SKU).
    public private(set) var entitySuggestion: EntitySuggestion? = nil

    // MARK: - Private

    private let baseActions: [CommandAction]
    private let context: CommandPaletteContext
    private let recentStore: RecentUsageStore
    private let contextActionBuilder: @Sendable (CommandPaletteContext) -> [CommandAction]

    // MARK: - Init

    public init(
        actions: [CommandAction],
        context: CommandPaletteContext,
        recentStore: RecentUsageStore = RecentUsageStore(),
        contextActionBuilder: @escaping @Sendable (CommandPaletteContext) -> [CommandAction] = { _ in [] }
    ) {
        self.baseActions = actions
        self.context = context
        self.recentStore = recentStore
        self.contextActionBuilder = contextActionBuilder
        refreshResults()
    }

    // MARK: - Keyboard navigation

    /// Move selection cursor down. Wraps past last item back to `nil`.
    public func moveSelectionDown() {
        guard !filteredResults.isEmpty else { return }
        if let current = selectedIndex {
            let next = current + 1
            selectedIndex = next < filteredResults.count ? next : nil
        } else {
            selectedIndex = 0
        }
    }

    /// Move selection cursor up. `nil` wraps to the last item.
    public func moveSelectionUp() {
        guard !filteredResults.isEmpty else { return }
        if let current = selectedIndex {
            selectedIndex = current > 0 ? current - 1 : nil
        } else {
            selectedIndex = filteredResults.count - 1
        }
    }

    /// Execute the currently selected action. No-op if nothing selected.
    public func executeSelected() {
        guard let index = selectedIndex, index < filteredResults.count else { return }
        let action = filteredResults[index]
        recentStore.record(id: action.id)
        action.handler()
        dismiss()
    }

    /// Select a result by index (used from tap gestures in the view).
    public func select(index: Int) {
        guard index < filteredResults.count else { return }
        selectedIndex = index
    }

    /// Execute a specific action by ID.
    public func execute(actionID: String) {
        guard let action = filteredResults.first(where: { $0.id == actionID }) else { return }
        recentStore.record(id: action.id)
        action.handler()
        dismiss()
    }

    /// Dismiss the palette.
    public func dismiss() {
        isDismissed = true
    }

    // MARK: - Private helpers

    private func refreshResults() {
        // Reset selection whenever results change
        selectedIndex = nil

        // Parse entity suggestion from query
        entitySuggestion = EntityParser.parse(query)

        // Context-specific actions prepended
        let contextActions = contextActionBuilder(context)

        if query.isEmpty {
            // Show context actions first, then all base actions sorted by recency
            let sorted = baseActions.sorted { lhs, rhs in
                recentStore.boost(for: lhs.id) > recentStore.boost(for: rhs.id)
            }
            filteredResults = contextActions + sorted
            return
        }

        // Score base actions against query (title + keywords)
        let scored: [(action: CommandAction, score: Double)] = baseActions.compactMap { action in
            let titleScore = FuzzyScorer.score(query: query, against: action.title)
            let keywordScore = action.keywords
                .map { FuzzyScorer.score(query: query, against: $0) }
                .max() ?? 0
            let best = max(titleScore, keywordScore)
            let boosted = best + recentStore.boost(for: action.id) * 5
            return best > 0 ? (action, boosted) : nil
        }

        let rankedBase = scored
            .sorted { $0.score > $1.score }
            .map { $0.action }

        // Score context actions too (but don't exclude zero-matches on context actions)
        let scoredContext: [(action: CommandAction, score: Double)] = contextActions.map { action in
            let titleScore = FuzzyScorer.score(query: query, against: action.title)
            let keywordScore = action.keywords
                .map { FuzzyScorer.score(query: query, against: $0) }
                .max() ?? 0
            let best = max(titleScore, keywordScore)
            return (action, best)
        }
        let rankedContext = scoredContext
            .filter { $0.score > 0 }
            .sorted { $0.score > $1.score }
            .map { $0.action }

        filteredResults = rankedContext + rankedBase
    }
}

// MARK: - Entity parser

enum EntityParser {
    /// Attempt to detect structured input: #ticket, phone, or SKU.
    static func parse(_ query: String) -> EntitySuggestion? {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        // Ticket number: #1234 or #ABCD-1234
        if trimmed.hasPrefix("#") {
            let candidate = String(trimmed.dropFirst())
            if !candidate.isEmpty && candidate.allSatisfy({ $0.isNumber || $0.isLetter || $0 == "-" }) {
                return .ticket(id: candidate)
            }
        }

        // Phone number: 10+ digit-rich string with optional dashes/parens/spaces
        let digitsOnly = trimmed.filter { $0.isNumber }
        if digitsOnly.count >= 7 {
            let nonPhone = trimmed.filter { !$0.isNumber && $0 != "-" && $0 != " " && $0 != "(" && $0 != ")" && $0 != "+" }
            if nonPhone.isEmpty {
                return .phone(number: digitsOnly)
            }
        }

        // SKU: uppercase alphanumeric with at least one dash, e.g. SKU-1234, PART-ABC-99
        let skuPattern = #"^[A-Z][A-Z0-9]+-[A-Z0-9-]+$"#
        if let _ = trimmed.range(of: skuPattern, options: [.regularExpression]) {
            return .sku(value: trimmed)
        }

        return nil
    }
}
