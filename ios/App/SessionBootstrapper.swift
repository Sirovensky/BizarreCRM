import Foundation
import Core
import Networking
import Persistence
import Auth

@MainActor
enum SessionBootstrapper {
    static func resolveInitialPhase(into state: AppState) async {
        do {
            try await Database.shared.open()
        } catch {
            AppLog.persistence.error("Database open failed: \(error.localizedDescription)")
        }

        // Push persisted server URL + token into the shared APIClient so
        // feature screens don't have to reach into Keychain themselves.
        await AppServices.shared.restoreSession()

        if TokenStore.shared.hasValidSession {
            state.phase = PINStore.shared.isEnrolled ? .locked : .authenticated
        } else {
            state.phase = .unauthenticated
        }

        // Warm reachability after the first view is on screen so NWPathMonitor
        // doesn't steal main-thread time during launch.
        Task.detached { @MainActor in
            Reachability.shared.start()
            // §20.3 — once reachability is live, kick off the orchestrator so
            // any queued offline mutations from the previous session flush as
            // soon as we're authenticated + online.
            SyncOrchestrator.shared.start()
        }
    }
}
