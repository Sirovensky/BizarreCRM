import Foundation
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

        if TokenStore.shared.hasValidSession {
            state.phase = PINStore.shared.isEnrolled ? .locked : .authenticated
        } else {
            state.phase = .unauthenticated
        }
    }
}
