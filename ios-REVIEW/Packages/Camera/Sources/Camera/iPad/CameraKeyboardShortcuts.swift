#if canImport(UIKit)
import SwiftUI
import DesignSystem

// MARK: - CameraKeyboardShortcuts

/// Keyboard shortcut bindings for the iPad camera UI.
///
/// | Key         | Action                        |
/// |-------------|-------------------------------|
/// | Space       | Capture photo                 |
/// | Escape      | Cancel / close camera         |
/// | ← / →       | Flip between front/back camera|
///
/// Apply via `.cameraKeyboardShortcuts(...)` view modifier on
/// ``CameraFullScreenLayout``.
public struct CameraKeyboardShortcuts: ViewModifier {

    private let onCapture: () -> Void
    private let onCancel: () -> Void
    private let onFlipCamera: (CameraLens) -> Void

    /// Current active lens — changes on ← / → arrow.
    @Binding private var activeLens: CameraLens

    public init(
        activeLens: Binding<CameraLens>,
        onCapture: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onFlipCamera: @escaping (CameraLens) -> Void
    ) {
        self._activeLens = activeLens
        self.onCapture = onCapture
        self.onCancel = onCancel
        self.onFlipCamera = onFlipCamera
    }

    public func body(content: Content) -> some View {
        content
            // Space → capture
            .keyboardShortcut(.space, modifiers: [])
            // Not a real modifier — we attach phantom buttons so the system
            // sees keyboardShortcut(.space) as a valid target. SwiftUI requires
            // a Button/control to own each shortcut.
            .overlay {
                shortcutButtons
            }
    }

    // MARK: - Phantom shortcut buttons (zero size, invisible)

    private var shortcutButtons: some View {
        ZStack {
            // Space — capture
            Button("Capture", action: onCapture)
                .keyboardShortcut(.space, modifiers: [])
                .accessibilityHidden(true)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityIdentifier("camera.kbd.capture")

            // Escape — cancel
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.escape, modifiers: [])
                .accessibilityHidden(true)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityIdentifier("camera.kbd.cancel")

            // Left arrow — flip to back
            Button("Back camera") {
                activeLens = .back
                onFlipCamera(.back)
            }
            .keyboardShortcut(.leftArrow, modifiers: [])
            .accessibilityHidden(true)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityIdentifier("camera.kbd.flipBack")

            // Right arrow — flip to front
            Button("Front camera") {
                activeLens = .front
                onFlipCamera(.front)
            }
            .keyboardShortcut(.rightArrow, modifiers: [])
            .accessibilityHidden(true)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityIdentifier("camera.kbd.flipFront")
        }
        .allowsHitTesting(false)
    }
}

// MARK: - CameraLens

/// Which physical camera is active.
public enum CameraLens: Sendable, Equatable {
    case back
    case front
}

// MARK: - View extension

public extension View {
    /// Attaches iPad keyboard shortcuts for camera operations.
    ///
    /// - Parameters:
    ///   - activeLens: Binding that tracks which camera is active (mutated on arrow keys).
    ///   - onCapture: Called when Space is pressed.
    ///   - onCancel: Called when Escape is pressed.
    ///   - onFlipCamera: Called with the new ``CameraLens`` when ← or → is pressed.
    func cameraKeyboardShortcuts(
        activeLens: Binding<CameraLens>,
        onCapture: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onFlipCamera: @escaping (CameraLens) -> Void
    ) -> some View {
        modifier(CameraKeyboardShortcuts(
            activeLens: activeLens,
            onCapture: onCapture,
            onCancel: onCancel,
            onFlipCamera: onFlipCamera
        ))
    }
}

// MARK: - ShortcutHintOverlay

/// Optional floating HUD showing available keyboard shortcuts.
///
/// Shown on `?` keypress or via `isVisible` binding. Auto-dismisses after 4 s.
/// Uses `.brandGlass(.regular)` so it sits naturally over the dark camera backdrop.
public struct ShortcutHintOverlay: View {

    @Binding var isVisible: Bool

    private static let hints: [(key: String, label: String)] = [
        ("Space",  "Capture photo"),
        ("Esc",    "Cancel"),
        ("←",      "Back camera"),
        ("→",      "Front camera"),
    ]

    public init(isVisible: Binding<Bool>) {
        self._isVisible = isVisible
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("Keyboard Shortcuts")
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreOnSurface)
                .padding(.bottom, DesignTokens.Spacing.xs)

            ForEach(Self.hints, id: \.key) { hint in
                HStack(spacing: DesignTokens.Spacing.lg) {
                    Text(hint.key)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.white)
                        .frame(minWidth: 44)
                        .padding(.horizontal, DesignTokens.Spacing.sm)
                        .padding(.vertical, DesignTokens.Spacing.xxs)
                        .background(Color.bizarreOnSurface.opacity(0.15),
                                    in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xs))
                        .accessibilityHidden(true)

                    Text(hint.label)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(hint.key): \(hint.label)")
            }
        }
        .padding(DesignTokens.Spacing.lg)
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .opacity(isVisible ? 1 : 0)
        .task(id: isVisible) {
            guard isVisible else { return }
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            withAnimation { isVisible = false }
        }
        .animation(.easeInOut(duration: DesignTokens.Motion.snappy), value: isVisible)
        .accessibilityHidden(!isVisible)
        .accessibilityLabel("Keyboard shortcuts panel")
    }
}

#endif
