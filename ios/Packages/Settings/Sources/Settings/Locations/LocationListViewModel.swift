import Foundation
import Observation

// MARK: - §60.1 LocationListViewModel

@Observable
@MainActor
public final class LocationListViewModel {

    // MARK: State

    public enum LoadState: Equatable {
        case idle, loading, loaded, error(String)
    }

    public private(set) var locations: [Location] = []
    public private(set) var loadState: LoadState = .idle
    public private(set) var isMutating: Bool = false

    // MARK: Sorting (iPad Table)

    public var sortOrder = [KeyPathComparator(\Location.name)]

    public var sortedLocations: [Location] {
        locations.sorted(using: sortOrder)
    }

    // MARK: Dependencies

    private let repo: any LocationRepository

    public init(repo: any LocationRepository) {
        self.repo = repo
    }

    // MARK: - Intents

    public func load() async {
        loadState = .loading
        do {
            locations = try await repo.fetchLocations()
            loadState = .loaded
        } catch {
            loadState = .error(error.localizedDescription)
        }
    }

    public func setPrimary(id: String) async {
        isMutating = true
        defer { isMutating = false }
        do {
            let updated = try await repo.setPrimary(id: id)
            locations = locations.map { loc in
                if loc.id == updated.id { return updated }
                // clear isPrimary on others
                var copy = loc
                copy = Location(
                    id: loc.id, name: loc.name,
                    addressLine1: loc.addressLine1, addressLine2: loc.addressLine2,
                    city: loc.city, region: loc.region, postal: loc.postal,
                    country: loc.country, phone: loc.phone, timezone: loc.timezone,
                    taxRateId: loc.taxRateId, active: loc.active, isPrimary: false,
                    openingHours: loc.openingHours
                )
                return copy
            }
        } catch {
            loadState = .error(error.localizedDescription)
        }
    }

    public func setActive(id: String, active: Bool) async {
        isMutating = true
        defer { isMutating = false }
        do {
            let updated = try await repo.setActive(id: id, active: active)
            locations = locations.map { $0.id == updated.id ? updated : $0 }
        } catch {
            loadState = .error(error.localizedDescription)
        }
    }

    public func delete(id: String) async {
        isMutating = true
        defer { isMutating = false }
        do {
            try await repo.deleteLocation(id: id)
            locations = locations.filter { $0.id != id }
        } catch {
            loadState = .error(error.localizedDescription)
        }
    }
}
