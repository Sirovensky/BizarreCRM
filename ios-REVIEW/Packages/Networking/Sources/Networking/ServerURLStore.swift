import Foundation

/// Lightweight persistent store for the selected server URL.
/// Kept separate from Keychain so the URL is readable without biometric unlock.
/// Used by LoginFlow (writes at SERVER + REGISTER steps) and by
/// AppServices (reads at launch to rehydrate the APIClient's base URL).
public enum ServerURLStore {
    private static let key = "bz.server_url"

    public static func save(_ url: URL) {
        UserDefaults.standard.set(url.absoluteString, forKey: key)
    }

    public static func load() -> URL? {
        UserDefaults.standard.string(forKey: key).flatMap(URL.init(string:))
    }

    public static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
