import Foundation
import Observation
import Networking

// MARK: - TrainingModeManager

/// §51 Training Mode state manager.
/// Persists `isActive` in UserDefaults and orchestrates demo token swapping.
@Observable
@MainActor
public final class TrainingModeManager {
    // MARK: - Public state

    public private(set) var isActive: Bool
    public private(set) var isLoading: Bool = false
    public private(set) var errorMessage: String?

    // MARK: - Private

    private let api: any APIClient
    private let defaults: UserDefaults
    private let tokenSwap: @MainActor @Sendable (String?) -> Void

    static let defaultsKey = "training_mode_active"

    // MARK: - Init

    public init(
        api: any APIClient,
        defaults: UserDefaults = .standard,
        tokenSwap: @escaping @MainActor @Sendable (String?) -> Void
    ) {
        self.api = api
        self.defaults = defaults
        self.tokenSwap = tokenSwap
        self.isActive = defaults.bool(forKey: TrainingModeManager.defaultsKey)
    }

    // MARK: - Enter / Exit

    public func enterTrainingMode() async {
        guard !isActive else { return }
        isLoading = true
        errorMessage = nil
        do {
            let response = try await api.enterTrainingMode()
            isActive = true
            defaults.set(true, forKey: TrainingModeManager.defaultsKey)
            tokenSwap(response.demoTenantToken)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    public func exitTrainingMode() {
        guard isActive else { return }
        isActive = false
        defaults.set(false, forKey: TrainingModeManager.defaultsKey)
        tokenSwap(nil)
        errorMessage = nil
    }

    // MARK: - Reset

    public func resetDemoData() async {
        guard isActive else { return }
        isLoading = true
        errorMessage = nil
        do {
            _ = try await api.resetDemoData()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
