import SwiftUI
import Observation

// §68.4 — CoachMarkView + CoachMarkDismissalStore
// Tooltip overlay shown the first time a user opens each top-level screen.
// "Don't show again" persisted per-screen in UserDefaults.

// MARK: - CoachMarkScreen

/// Identifies a top-level screen that may show a coach mark.
public enum CoachMarkScreen: String, CaseIterable, Sendable {
    case dashboard
    case tickets
    case customers
    case pos
    case inventory
    case invoices
    case reports
    case employees
    case settings
}

// MARK: - CoachMarkDismissalStore

/// Persists the set of screens whose coach marks have been dismissed.
///
/// Backed by `UserDefaults`. All reads/writes are O(1) key lookups.
@Observable
public final class CoachMarkDismissalStore: @unchecked Sendable {

    // MARK: Shared instance

    public static let shared = CoachMarkDismissalStore()

    // MARK: Private

    private let defaults: UserDefaults
    private static let keyPrefix = "com.bizarrecrm.coachmark.dismissed."

    // MARK: Init

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: Public API

    /// Returns `true` if the coach mark for `screen` has been dismissed.
    public func isDismissed(_ screen: CoachMarkScreen) -> Bool {
        defaults.bool(forKey: key(for: screen))
    }

    /// Marks `screen`'s coach mark as dismissed and persists immediately.
    public func dismiss(_ screen: CoachMarkScreen) {
        defaults.set(true, forKey: key(for: screen))
    }

    /// Resets all dismissals (e.g. for testing or "reset hints" in Settings).
    public func resetAll() {
        for screen in CoachMarkScreen.allCases {
            defaults.removeObject(forKey: key(for: screen))
        }
    }

    // MARK: Private

    private func key(for screen: CoachMarkScreen) -> String {
        Self.keyPrefix + screen.rawValue
    }
}

// MARK: - CoachMarkOverlay

/// A tooltip overlay for a screen's coach mark.
///
/// Rendered above the content via `.overlay`. Respects VoiceOver:
/// the dismiss button has a clear accessibility label and hint.
///
/// Example usage:
/// ```swift
/// SomeView()
///     .coachMark(.dashboard, title: "Welcome to Dashboard",
///                message: "Your daily overview lives here.")
/// ```
public struct CoachMarkOverlay: View {

    let screen: CoachMarkScreen
    let title: String
    let message: String
    @State private var shown: Bool = false

    @State private var store = CoachMarkDismissalStore.shared

    public init(screen: CoachMarkScreen, title: String, message: String) {
        self.screen  = screen
        self.title   = title
        self.message = message
    }

    public var body: some View {
        if shown {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title)
                        .font(.headline)
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Dismiss coach mark for \(title)")
                    .accessibilityHint("Hides this tip. Use 'Don't show again' to hide permanently.")
                }

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button("Don't show again") {
                    store.dismiss(screen)
                    shown = false
                }
                .font(.caption.bold())
                .foregroundStyle(.bizarreOrange)
                .accessibilityLabel("Don't show this tip again")
                .accessibilityHint("Permanently hides this coach mark for \(title)")
            }
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Coach mark: \(title)")
        }
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.2)) {
            shown = false
        }
    }

    private func onAppear() {
        if !store.isDismissed(screen) {
            withAnimation(.easeOut(duration: 0.25).delay(0.3)) {
                shown = true
            }
        }
    }
}

// MARK: - View extension

public extension View {

    /// Overlays a coach mark tooltip for `screen`.
    ///
    /// The mark is shown only once per screen; "Don't show again" persists
    /// the dismissal to `UserDefaults`.
    func coachMark(
        _ screen: CoachMarkScreen,
        title: String,
        message: String
    ) -> some View {
        self.overlay(alignment: .top) {
            CoachMarkOverlay(screen: screen, title: title, message: message)
        }
    }
}

#if DEBUG
#Preview {
    Text("Content below")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coachMark(.dashboard,
                   title: "Welcome to Dashboard",
                   message: "Your sales, tickets, and clock are all here.")
}
#endif
