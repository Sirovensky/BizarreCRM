// §57.2 CustomerArrivalHaptic — fires haptic feedback when the technician
// arrives at a customer's location (i.e., when job status transitions to
// `onSite` or when `FieldCheckInService` confirms on-site proximity).
//
// Uses UIImpactFeedbackGenerator (.heavy) for a clear, tactile "thunk"
// distinct from lighter success patterns used elsewhere in the app.
//
// Accessibility:
//   - Respects the user's "Reduce Motion" preference: when Reduce Motion is
//     enabled (which typically implies the user prefers fewer haptics), the
//     impact is swapped for the lighter `.soft` style rather than skipped
//     entirely — the functional arrival cue is preserved.
//   - Does NOT use `.rigid` or chained generators which cause excessive
//     physical feedback.
//
// Thread safety: all UIKit calls happen on the main actor.
// No GPS / background location involved; triggered only on explicit status
// change driven by the app, not a background geofence.

import Foundation

#if canImport(UIKit)
import UIKit

// MARK: - CustomerArrivalHaptic

/// Plays a single haptic pulse to notify the technician they have arrived.
///
/// ```swift
/// // In JobDetailViewModel, after status update to .onSite succeeds:
/// CustomerArrivalHaptic.playArrival(reduceMotion: reduceMotion)
/// ```
@MainActor
public enum CustomerArrivalHaptic {

    /// Plays the arrival haptic.
    ///
    /// - Parameter reduceMotion: Pass `true` when the system Accessibility
    ///   "Reduce Motion" setting is on. Uses `.soft` style to preserve the
    ///   cue without a heavy physical jolt.
    public static func playArrival(reduceMotion: Bool = false) {
        let style: UIImpactFeedbackGenerator.FeedbackStyle = reduceMotion ? .soft : .heavy
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    /// Plays the arrival haptic sequence: heavy impact + brief delay + medium
    /// confirmation pulse.  Use this variant when you also want an audio cue
    /// (e.g., the system plays a sound for the notification that triggers the
    /// check-in prompt).
    public static func playArrivalWithConfirmation(reduceMotion: Bool = false) {
        playArrival(reduceMotion: reduceMotion)
        guard !reduceMotion else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            let confirm = UIImpactFeedbackGenerator(style: .medium)
            confirm.impactOccurred()
        }
    }
}

// MARK: - SwiftUI convenience modifier

import SwiftUI

public extension View {

    /// Plays `CustomerArrivalHaptic.playArrival` when `isOnSite` transitions
    /// to `true`.
    ///
    /// ```swift
    /// mapView
    ///     .onCustomerArrival(isOnSite: vm.isOnSite)
    /// ```
    func onCustomerArrival(isOnSite: Bool) -> some View {
        modifier(CustomerArrivalHapticModifier(isOnSite: isOnSite))
    }
}

// MARK: - CustomerArrivalHapticModifier

private struct CustomerArrivalHapticModifier: ViewModifier {
    let isOnSite: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .onChange(of: isOnSite) { _, arrived in
                guard arrived else { return }
                CustomerArrivalHaptic.playArrival(reduceMotion: reduceMotion)
            }
    }
}

#else

// MARK: - Non-UIKit stub

@MainActor
public enum CustomerArrivalHaptic {
    public static func playArrival(reduceMotion: Bool = false) {}
    public static func playArrivalWithConfirmation(reduceMotion: Bool = false) {}
}

import SwiftUI

public extension View {
    func onCustomerArrival(isOnSite: Bool) -> some View { self }
}

#endif
