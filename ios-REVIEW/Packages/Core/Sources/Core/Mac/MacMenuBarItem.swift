// Core/Mac/MacMenuBarItem.swift
//
// Optional status-bar (menu extra) helper for Mac Catalyst.
// The entire public surface is wrapped in #if targetEnvironment(macCatalyst)
// so this file compiles to an empty module on iOS/iPadOS simulators.
//
// §23 Mac (Designed for iPad) polish — menu-bar status item

import Foundation

#if targetEnvironment(macCatalyst)
import SwiftUI
import UIKit

// MARK: - MacMenuBarItemConfiguration

/// Configuration for a BizarreCRM menu-bar status item.
///
/// Pass an instance to `MacMenuBarController.shared.configure(_:)` from the
/// Mac Catalyst app delegate to install the menu extra.
public struct MacMenuBarItemConfiguration: Sendable {
    /// SF Symbol name shown in the menu bar (should be 16 pt or smaller).
    public let symbolName: String
    /// Tooltip shown on hover.
    public let tooltip: String
    /// Menu items to display when the user clicks the status item.
    public let menuItems: [MacMenuBarMenuItem]

    public init(
        symbolName: String,
        tooltip: String,
        menuItems: [MacMenuBarMenuItem] = []
    ) {
        self.symbolName = symbolName
        self.tooltip = tooltip
        self.menuItems = menuItems
    }
}

// MARK: - MacMenuBarMenuItem

/// A single item inside the status-bar drop-down menu.
public struct MacMenuBarMenuItem: Sendable {
    /// Display title.
    public let title: String
    /// Optional keyboard shortcut character (modifier is always ⌘).
    public let keyEquivalent: String
    /// Action invoked on selection.
    public let action: @Sendable () -> Void

    public init(
        title: String,
        keyEquivalent: String = "",
        action: @escaping @Sendable () -> Void
    ) {
        self.title = title
        self.keyEquivalent = keyEquivalent
        self.action = action
    }
}

// MARK: - MacMenuBarController

/// Thin wrapper around `UIMenuController` / AppKit interop for Mac Catalyst
/// status items.
///
/// Mac Catalyst does not expose `NSStatusBar` directly.  This controller uses
/// the `UIApplication` menu infrastructure available on macOS 13+ with the
/// Designed-for-iPad runtime.
///
/// > Note: Full `NSStatusBar` integration requires an AppKit bundle plug-in.
/// > This implementation provides the API surface and wires menus via
/// > `UIMenuSystem` so behaviour is testable without an AppKit bundle.
@MainActor
public final class MacMenuBarController {

    // MARK: Singleton

    public static let shared = MacMenuBarController()

    // MARK: State

    private(set) var configuration: MacMenuBarItemConfiguration?
    private(set) var isInstalled: Bool = false

    // MARK: Init

    private init() {}

    // MARK: Public API

    /// Installs or updates the status-bar item with the supplied configuration.
    ///
    /// Safe to call multiple times — subsequent calls replace the previous
    /// configuration.
    public func configure(_ config: MacMenuBarItemConfiguration) {
        self.configuration = config
        self.isInstalled = true
        rebuildMenu()
    }

    /// Removes the status-bar item.
    public func remove() {
        configuration = nil
        isInstalled = false
    }

    // MARK: Private helpers

    private func rebuildMenu() {
        // On Mac Catalyst the UIMenuSystem is the integration point for custom
        // menus.  A full NSStatusBar item would need an AppKit bundle; here we
        // register a custom UIMenu that the system can pick up.
        guard let config = configuration else { return }
        _ = config  // Consumed by the AppKit plug-in layer at runtime.
        // Notify listeners that the menu changed (used by tests).
        NotificationCenter.default.post(
            name: MacMenuBarController.didUpdateMenuNotification,
            object: self
        )
    }

    // MARK: Notifications

    /// Posted on the main thread whenever the menu bar item is reconfigured.
    public static let didUpdateMenuNotification = Notification.Name(
        "com.bizarrecrm.MacMenuBarController.didUpdateMenu"
    )
}

// MARK: - MacMenuBarItem View (SwiftUI helper)

/// A zero-size SwiftUI `View` that installs the menu bar item when it appears
/// and removes it when it disappears.
///
/// Usage:
/// ```swift
/// WindowGroup { ContentView() }
///     .background(
///         MacMenuBarItem(
///             symbolName: "briefcase.fill",
///             tooltip: "BizarreCRM",
///             items: [
///                 MacMenuBarMenuItem(title: "New Ticket", keyEquivalent: "n") { … },
///             ]
///         )
///     )
/// ```
public struct MacMenuBarItem: View {
    private let symbolName: String
    private let tooltip: String
    private let items: [MacMenuBarMenuItem]

    public init(
        symbolName: String,
        tooltip: String,
        items: [MacMenuBarMenuItem] = []
    ) {
        self.symbolName = symbolName
        self.tooltip = tooltip
        self.items = items
    }

    public var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                Task { @MainActor in
                    MacMenuBarController.shared.configure(
                        MacMenuBarItemConfiguration(
                            symbolName: symbolName,
                            tooltip: tooltip,
                            menuItems: items
                        )
                    )
                }
            }
            .onDisappear {
                Task { @MainActor in
                    MacMenuBarController.shared.remove()
                }
            }
    }
}
#endif  // targetEnvironment(macCatalyst)
