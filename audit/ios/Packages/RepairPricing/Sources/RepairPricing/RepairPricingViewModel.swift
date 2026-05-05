import Foundation
import Observation
import Core
import Networking

/// Loading state for async catalog fetches.
public enum RepairPricingState: Sendable, Equatable {
    case loading
    case loaded
    case failed(String)
}

/// ViewModel backing the catalog browser and service picker.
///
/// `family` filters the displayed templates to a single device family (e.g.
/// "Apple"). Setting it to `nil` shows all families.
/// `searchQuery` is debounced 300 ms before triggering a reload.
@MainActor
@Observable
public final class RepairPricingViewModel {
    // MARK: - Public state

    public private(set) var state: RepairPricingState = .loading
    public private(set) var templates: [DeviceTemplate] = []
    public private(set) var services: [RepairService] = []

    /// Selected family chip filter. `nil` = All.
    public var family: String? = nil {
        didSet { guard family != oldValue else { return }; scheduleReload() }
    }

    /// Live search query — 300 ms debounced.
    public var searchQuery: String = ""

    /// Distinct families derived from loaded templates, always including "All".
    public var availableFamilies: [String] {
        let raw = templates
            .compactMap { $0.family }
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        return raw.filter { seen.insert($0).inserted }
    }

    /// Templates after family + search filtering.
    public var filteredTemplates: [DeviceTemplate] {
        var result = templates
        if let f = family, !f.isEmpty {
            result = result.filter { $0.family?.lowercased() == f.lowercased() }
        }
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return result }
        return result.filter { t in
            t.name.lowercased().contains(q) ||
            (t.model?.lowercased().contains(q) == true) ||
            (t.family?.lowercased().contains(q) == true)
        }
    }

    // MARK: - Private

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private var searchDebounceTask: Task<Void, Never>?

    public init(api: APIClient) {
        self.api = api
    }

    // MARK: - Public API

    /// Initial / pull-to-refresh load.
    public func load() async {
        state = .loading
        do {
            async let t = api.listDeviceTemplates()
            async let s = api.listRepairServices()
            let (newTemplates, newServices) = try await (t, s)
            templates = newTemplates
            services = newServices
            state = .loaded
        } catch {
            AppLog.ui.error("RepairPricing load failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }

    /// Called by the search field `onChange` — debounces 300 ms.
    public func onSearchChange(_ query: String) {
        searchQuery = query
        searchDebounceTask?.cancel()
        searchDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            // Search is purely local filtering — no network call needed
            // unless a future version uses server-side search.
        }
    }

    // MARK: - Private helpers

    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task { @MainActor in
            await load()
        }
    }
}
