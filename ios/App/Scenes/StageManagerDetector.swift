import UIKit
import Observation

// MARK: - StageManagerDetector

/// Observes the number of connected UIWindowScenes to infer whether Stage
/// Manager is active on the current iPad.
///
/// **Usage in SwiftUI**
/// ```swift
/// @State private var detector = StageManagerDetector.shared
///
/// var body: some View {
///     content
///         .padding(detector.isStageManagerActive ? .bsSm : .bsMd)
/// }
/// ```
///
/// **Derivation logic**
/// Stage Manager is considered "active" when:
/// 1. The device idiom is `.pad`, AND
/// 2. `UIApplication.shared.connectedScenes.count > 1`
///    (a second scene exists only when Stage Manager creates / restores it).
///
/// This is a best-effort heuristic — Apple provides no public API that
/// directly exposes Stage Manager state. The count is refreshed on every
/// `UIScene.didActivateNotification` and `UIScene.didDisconnectNotification`.
@MainActor
@Observable
public class StageManagerDetector: @unchecked Sendable {

    // MARK: Singleton

    public static let shared = StageManagerDetector()

    // MARK: Observable state

    /// `true` when running on iPad with more than one connected scene,
    /// which is a reliable proxy for Stage Manager being active.
    /// `internal(set)` to allow test doubles to set values directly.
    public internal(set) var isStageManagerActive: Bool = false

    /// Raw count of connected scenes; useful for debugging and tests.
    /// `internal(set)` to allow test doubles to set values directly.
    public internal(set) var connectedSceneCount: Int = 0

    // MARK: Init

    private var observations: [NSObjectProtocol] = []

    /// Designated initialiser. `internal` so test doubles can call `super.init()`.
    init() {
        refresh()
        startObserving()
    }

    deinit {
        observations.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: - Internal

    /// Re-reads connected scene count. `@objc dynamic` allows tests to override.
    func refresh() {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            isStageManagerActive = false
            connectedSceneCount = 0
            return
        }
        let count = UIApplication.shared.connectedScenes.count
        connectedSceneCount = count
        isStageManagerActive = count > 1
    }

    private func startObserving() {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            UIScene.didActivateNotification,
            UIScene.didDisconnectNotification,
            UIScene.willConnectNotification,
        ]
        observations = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refresh()
                }
            }
        }
    }
}
