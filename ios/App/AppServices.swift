import Foundation
import Networking
import Persistence
import Auth
import Settings

/// Shared services that must share state across the whole app. Most
/// importantly the APIClient: LoginFlow writes the bearer token and base URL
/// to this instance, Dashboard and every other feature reads from the same
/// instance so the session carries. Replace with a full Factory container
/// once more features come online.
@MainActor
final class AppServices {
    static let shared = AppServices()

    let apiClient: APIClient

    private init() {
        self.apiClient = APIClientImpl(initialBaseURL: ServerURLStore.load())
        // Expose to packages that can't import Auth/App (Settings, etc.).
        APIClientHolder.current = self.apiClient
    }

    /// Push any persisted credentials into the APIClient. Call once at launch
    /// so a cold-started user with a valid session doesn't need to re-auth.
    func restoreSession() async {
        if let token = TokenStore.shared.accessToken {
            await apiClient.setAuthToken(token)
        }
        if let url = ServerURLStore.load() {
            await apiClient.setBaseURL(url)
        }
    }
}
