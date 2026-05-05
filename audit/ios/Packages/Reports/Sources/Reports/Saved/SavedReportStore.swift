import Foundation

// MARK: - SavedReportStore

/// Actor-isolated, UserDefaults-backed store for `SavedReportView` values.
///
/// All mutations are atomic within the actor. Persistence uses the shared
/// App Group suite (`group.com.bizarrecrm`) so the widget extension and
/// main app share the same saved views.
///
/// Ordering: views are returned newest-first (descending `createdDate`).
public actor SavedReportStore {

    // MARK: Constants

    private static let defaultsKey = "com.bizarrecrm.savedReportViews"
    private static let appGroupSuite = "group.com.bizarrecrm"

    // MARK: Storage

    private let defaults: UserDefaults
    private var cache: [SavedReportView] = []

    // MARK: Init

    /// Production init — uses the shared App Group suite.
    public init() {
        self.defaults = UserDefaults(suiteName: Self.appGroupSuite) ?? .standard
        self.cache = Self.load(from: defaults)
    }

    /// Testable init — callers supply their own `UserDefaults` instance.
    public init(defaults: UserDefaults) {
        self.defaults = defaults
        self.cache = Self.load(from: defaults)
    }

    // MARK: - Read

    /// All saved views, sorted newest-first.
    public var all: [SavedReportView] {
        cache.sorted { $0.createdDate > $1.createdDate }
    }

    /// Fetch a single view by ID, or nil if not found.
    public func view(withID id: UUID) -> SavedReportView? {
        cache.first { $0.id == id }
    }

    // MARK: - Write

    /// Persist a new saved view. Throws `SavedReportStoreError.duplicateName`
    /// when another view with the same trimmed name already exists.
    public func save(_ view: SavedReportView) throws {
        let trimmed = view.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SavedReportStoreError.emptyName }
        let hasDuplicate = cache.contains { existing in
            existing.id != view.id &&
            existing.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(trimmed) == .orderedSame
        }
        guard !hasDuplicate else { throw SavedReportStoreError.duplicateName(trimmed) }
        // Replace if same ID already present; otherwise append.
        if let idx = cache.firstIndex(where: { $0.id == view.id }) {
            cache[idx] = view
        } else {
            cache.append(view)
        }
        persist()
    }

    /// Delete the view with the given ID. No-op if not found.
    public func delete(id: UUID) {
        cache.removeAll { $0.id == id }
        persist()
    }

    /// Remove all saved views.
    public func deleteAll() {
        cache.removeAll()
        persist()
    }

    // MARK: - Private helpers

    private func persist() {
        do {
            let data = try JSONEncoder().encode(cache)
            defaults.set(data, forKey: Self.defaultsKey)
        } catch {
            // Non-fatal: next app launch will reload from the last good state.
        }
    }

    private static func load(from defaults: UserDefaults) -> [SavedReportView] {
        guard let data = defaults.data(forKey: defaultsKey) else { return [] }
        return (try? JSONDecoder().decode([SavedReportView].self, from: data)) ?? []
    }
}

// MARK: - SavedReportStoreError

public enum SavedReportStoreError: Error, Equatable, LocalizedError {
    case emptyName
    case duplicateName(String)

    public var errorDescription: String? {
        switch self {
        case .emptyName:
            return "View name must not be empty."
        case .duplicateName(let name):
            return "A saved view named \"\(name)\" already exists."
        }
    }
}
