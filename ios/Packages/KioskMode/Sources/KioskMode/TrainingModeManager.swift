import Foundation
import Observation
import Networking
import Core

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
        // BUGHUNT-2026-05-17: re-entry guard. Without this, a rapid double-tap
        // of "Enter Training Mode" before the first POST returns lets two
        // `api.enterTrainingMode()` calls fire in parallel. Server creates two
        // demo tenants, two audit rows, and the second response's token swap
        // races the first — UI can end up wired to a tenant the user never
        // sees in the audit log. `isActive` doesn't flip until success so it
        // can't serve as a re-entry guard here.
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            let response = try await api.enterTrainingMode()
            isActive = true
            defaults.set(true, forKey: TrainingModeManager.defaultsKey)
            tokenSwap(response.demoTenantToken)
        } catch let e where AppError.isCancellation(e) {
            // BUGHUNT-2026-05-17: cancellation (user dismissed the settings
            // sheet mid-POST, or the parent Task was torn down) previously
            // painted "The operation was cancelled" as an errorMessage banner
            // on the Training settings row, tempting the user to tap Enter
            // again — that second tap spawns a parallel POST /training/enter
            // and the server creates a second demo tenant + audit row. Stay
            // silent; the user can re-tap explicitly if they still want
            // training mode.
            isLoading = false
            return
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
        // BUGHUNT-2026-05-17: re-entry guard. Reset reseeds the entire demo
        // tenant — a duplicate POST while one is in flight wipes the seed a
        // second time mid-write, which on a slow seed step has caused
        // half-seeded rows the user sees as ghost data after the second pass
        // finishes. Short-circuit re-entry.
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            _ = try await api.resetDemoData()
        } catch let e where AppError.isCancellation(e) {
            // BUGHUNT-2026-05-17: cancellation (settings sheet dismissed,
            // navigation popped) previously painted the reset banner as
            // "Failed: cancelled" — the server-side reseed has likely already
            // begun (the request was issued, the response was the casualty),
            // so painting failure tempts re-tap and the second POST starts a
            // SECOND reseed while the first is still running. Stay silent;
            // server will finish the in-flight reseed regardless of whether
            // we wait for its response.
            isLoading = false
            return
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
