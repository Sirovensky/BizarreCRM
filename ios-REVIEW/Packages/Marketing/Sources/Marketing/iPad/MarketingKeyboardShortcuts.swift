import SwiftUI
import DesignSystem

// MARK: - MarketingShortcutDescriptor (platform-independent, testable)

/// Stable descriptor for a single registered Marketing keyboard shortcut.
/// `Character`-based to keep tests free of SwiftUI imports.
public struct MarketingShortcutDescriptor: Sendable, Hashable {
    /// The key character that maps to `KeyEquivalent`.
    public let key: Character
    /// Modifier flags raw UInt (EventModifierFlags.command = 1_048_576).
    public let modifierFlags: UInt
    /// Human-readable label for the discoverability overlay.
    public let title: String

    public init(key: Character, modifierFlags: UInt, title: String) {
        self.key = key
        self.modifierFlags = modifierFlags
        self.title = title
    }
}

// MARK: - MarketingShortcutRegistry

/// All keyboard shortcuts registered for the Marketing iPad feature.
/// Test targets import this without needing SwiftUI.
///
/// Shortcut catalog (all ⌘-modified):
///   ⌘N     New campaign
///   ⌘R     Refresh list
///   ⌘⏎    Send / Run Now
///   ⌘D     Duplicate selected campaign
///   ⌘1–4   Switch sidebar kind
public enum MarketingShortcutRegistry {

    // EventModifierFlags.command raw value
    private static let cmd: UInt = 1_048_576

    public static let newCampaign = MarketingShortcutDescriptor(
        key: "n",
        modifierFlags: cmd,
        title: "New Campaign"
    )

    public static let refresh = MarketingShortcutDescriptor(
        key: "r",
        modifierFlags: cmd,
        title: "Refresh"
    )

    // Return key is represented as "\r" (carriage return)
    public static let runNow = MarketingShortcutDescriptor(
        key: "\r",
        modifierFlags: cmd,
        title: "Run Now"
    )

    public static let duplicate = MarketingShortcutDescriptor(
        key: "d",
        modifierFlags: cmd,
        title: "Duplicate Campaign"
    )

    public static let kindCampaigns = MarketingShortcutDescriptor(
        key: "1",
        modifierFlags: cmd,
        title: "Go to Campaigns"
    )

    public static let kindCoupons = MarketingShortcutDescriptor(
        key: "2",
        modifierFlags: cmd,
        title: "Go to Coupons"
    )

    public static let kindReferrals = MarketingShortcutDescriptor(
        key: "3",
        modifierFlags: cmd,
        title: "Go to Referrals"
    )

    public static let kindReviews = MarketingShortcutDescriptor(
        key: "4",
        modifierFlags: cmd,
        title: "Go to Reviews"
    )

    /// All registered shortcuts in declaration order.
    public static let all: [MarketingShortcutDescriptor] = [
        newCampaign, refresh, runNow, duplicate,
        kindCampaigns, kindCoupons, kindReferrals, kindReviews
    ]
}

// MARK: - MarketingKeyboardShortcutsModifier

public struct MarketingKeyboardShortcutsModifier: ViewModifier {
    public let onNewCampaign:  () -> Void
    public let onRefresh:      () -> Void
    public let onRunNow:       () -> Void
    public let onDuplicate:    () -> Void
    public let onKindChange:   (MarketingKind) -> Void

    public init(
        onNewCampaign:  @escaping () -> Void,
        onRefresh:      @escaping () -> Void,
        onRunNow:       @escaping () -> Void,
        onDuplicate:    @escaping () -> Void,
        onKindChange:   @escaping (MarketingKind) -> Void
    ) {
        self.onNewCampaign = onNewCampaign
        self.onRefresh     = onRefresh
        self.onRunNow      = onRunNow
        self.onDuplicate   = onDuplicate
        self.onKindChange  = onKindChange
    }

    public func body(content: Content) -> some View {
        content.overlay {
            shortcutButtons
        }
    }

    // Hidden zero-frame buttons — idiomatic SwiftUI keyboard shortcut attachment.
    @ViewBuilder
    private var shortcutButtons: some View {
        Group {
            shortcutButton(action: onNewCampaign, equiv: "n")
            shortcutButton(action: onRefresh,     equiv: "r")
            shortcutButton(action: onRunNow,      equiv: "\r")
            shortcutButton(action: onDuplicate,   equiv: "d")
            shortcutButton(action: { onKindChange(.campaigns) },  equiv: "1")
            shortcutButton(action: { onKindChange(.coupons) },    equiv: "2")
            shortcutButton(action: { onKindChange(.referrals) },  equiv: "3")
            shortcutButton(action: { onKindChange(.reviews) },    equiv: "4")
        }
    }

    private func shortcutButton(action: @escaping () -> Void, equiv: Character) -> some View {
        Button(action: action) { EmptyView() }
            #if canImport(UIKit)
            .keyboardShortcut(KeyEquivalent(equiv), modifiers: .command)
            #endif
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }
}

public extension View {
    func marketingKeyboardShortcuts(
        onNewCampaign:  @escaping () -> Void,
        onRefresh:      @escaping () -> Void,
        onRunNow:       @escaping () -> Void,
        onDuplicate:    @escaping () -> Void,
        onKindChange:   @escaping (MarketingKind) -> Void
    ) -> some View {
        modifier(MarketingKeyboardShortcutsModifier(
            onNewCampaign: onNewCampaign,
            onRefresh:     onRefresh,
            onRunNow:      onRunNow,
            onDuplicate:   onDuplicate,
            onKindChange:  onKindChange
        ))
    }
}
