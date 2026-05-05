import SwiftUI

// §22.4 Multi-window / Stage Manager — SwiftUI capture modifier

// MARK: - WindowSceneStateCaptureModifier

/// A `ViewModifier` that writes `state` into `WindowSceneStateStore`
/// whenever the binding's value changes or the view disappears.
///
/// Attach via the `.captureWindowState(_:sessionId:store:)` convenience.
///
/// ## Usage
/// ```swift
/// ContentView()
///     .captureWindowState($windowState, sessionId: session.persistentIdentifier)
/// ```
@MainActor
private struct WindowSceneStateCaptureModifier: ViewModifier {

    // MARK: - Properties

    /// Live binding that the host view keeps up to date.
    @Binding var state: WindowSceneState

    /// `UISceneSession.persistentIdentifier` of the owning window.
    let sessionId: String

    /// Store to write into; defaults to the shared singleton.
    let store: WindowSceneStateStore

    // MARK: - Body

    func body(content: Content) -> some View {
        content
            .onChange(of: state) { _, newState in
                store.save(newState, for: sessionId)
            }
            .onDisappear {
                store.save(state, for: sessionId)
            }
    }
}

// MARK: - View extension

public extension View {

    /// Captures `state` into `store` whenever it changes and on disappear,
    /// so the window can be restored to the same position on next launch.
    ///
    /// - Parameters:
    ///   - state: Binding to the scene's `WindowSceneState`.
    ///   - sessionId: `UISceneSession.persistentIdentifier` of the window.
    ///   - store: Persistence store; defaults to a shared `WindowSceneStateStore`.
    @MainActor
    func captureWindowState(
        _ state: Binding<WindowSceneState>,
        sessionId: String,
        store: WindowSceneStateStore = WindowSceneStateStore()
    ) -> some View {
        modifier(
            WindowSceneStateCaptureModifier(
                state: state,
                sessionId: sessionId,
                store: store
            )
        )
    }
}
