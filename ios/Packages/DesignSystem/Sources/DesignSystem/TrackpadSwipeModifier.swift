import SwiftUI

// §22.6 — Swipe gestures translated to trackpad (2-finger).
//
// On iPad with a Magic Keyboard / trackpad and on Mac (Designed-for-iPad),
// users expect 2-finger horizontal swipes to invoke the same row actions
// that touch swipe-from-edge does.  SwiftUI's `.swipeActions` already wires
// touch swipes; this modifier adds the trackpad equivalent by attaching a
// `DragGesture` (which on indirect input devices receives 2-finger pan
// events from the trackpad) and translating it into the same callbacks.
//
// Usage:
//   RowView()
//       .swipeActions { … }                // touch
//       .brandTrackpadSwipe(                // trackpad 2-finger pan
//           leading:  { archive() },
//           trailing: { delete() }
//       )

// MARK: - Constants

/// Activation thresholds for `brandTrackpadSwipe` (§22.6).
public enum TrackpadSwipeThresholds {
    /// Minimum horizontal translation (points) before a swipe fires.
    public static let activation: CGFloat = 60
    /// Maximum vertical drift permitted while still treating the gesture
    /// as horizontal (filters out scroll-style 2-finger pans).
    public static let verticalTolerance: CGFloat = 20
}

// MARK: - TrackpadSwipeModifier

/// Attaches a horizontal `DragGesture` that fires `leading` on a
/// right-going pan and `trailing` on a left-going pan, mirroring the
/// `.swipeActions` semantics on touch.
///
/// Indirect-input gestures from a trackpad arrive through the same
/// `DragGesture` pipeline on iPadOS 13.4+ / Catalyst, so the same code
/// path covers Magic Keyboard 2-finger pans and Mac trackpad swipes.
public struct TrackpadSwipeModifier: ViewModifier {

    public typealias Action = () -> Void

    private let leading: Action?
    private let trailing: Action?

    @State private var didFire = false

    public init(leading: Action?, trailing: Action?) {
        self.leading = leading
        self.trailing = trailing
    }

    public func body(content: Content) -> some View {
        content.gesture(
            DragGesture(minimumDistance: TrackpadSwipeThresholds.activation)
                .onChanged { value in
                    guard !didFire else { return }
                    let dx = value.translation.width
                    let dy = abs(value.translation.height)
                    guard dy <= TrackpadSwipeThresholds.verticalTolerance else { return }
                    if dx >= TrackpadSwipeThresholds.activation {
                        didFire = true
                        leading?()
                    } else if dx <= -TrackpadSwipeThresholds.activation {
                        didFire = true
                        trailing?()
                    }
                }
                .onEnded { _ in didFire = false }
        )
    }
}

// MARK: - View extension

public extension View {

    /// Wires trackpad 2-finger horizontal pan to the same actions exposed by
    /// `.swipeActions` (§22.6).
    ///
    /// - Parameters:
    ///   - leading: Fired on a rightward pan (mirrors `edge: .leading`).
    ///   - trailing: Fired on a leftward pan (mirrors `edge: .trailing`).
    /// - Returns: A view that recognises horizontal trackpad pans and
    ///   forwards them to the supplied closures.
    func brandTrackpadSwipe(
        leading: (() -> Void)? = nil,
        trailing: (() -> Void)? = nil
    ) -> some View {
        modifier(TrackpadSwipeModifier(leading: leading, trailing: trailing))
    }
}
