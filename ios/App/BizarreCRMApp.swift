import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import Core
import DesignSystem
import Networking
import Persistence
import Auth
import Sync

@main
struct BizarreCRMApp: App {
    @State private var appState = AppState()

    init() {
        ContainerBootstrap.registerDefaults()
        BrandFonts.registerIfNeeded()
    }

    var body: some Scene {
        let scene = WindowGroup {
            RootView()
                .environment(appState)
                .tint(.bizarreOrange)
                .preferredColorScheme(appState.forcedColorScheme)
                .onOpenURL { url in
                    DeepLinkRouter.shared.handle(url)
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL {
                        DeepLinkRouter.shared.handle(url)
                    }
                }
        }
        .commands {
            // §22.3 — Menu bar: iPad-specific .commands with grouped menu items
            // File group — replaces system "New Item" with BizarreCRM-specific actions
            CommandGroup(replacing: .newItem) {
                Button("New Ticket") {
                    DeepLinkRouter.shared.handle(URL(string: "bizarrecrm://ticket/new")!)
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Sync Now") {
                    Task { @MainActor in await SyncManager.shared.syncNow() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }

            // Edit group — Find shortcut
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Find…") {
                    DeepLinkRouter.shared.handle(URL(string: "bizarrecrm://search")!)
                }
                .keyboardShortcut("f", modifiers: .command)
            }

            // View menu — navigation shortcuts
            CommandMenu("View") {
                Button("Dashboard") {
                    DeepLinkRouter.shared.handle(URL(string: "bizarrecrm://dashboard")!)
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Tickets") {
                    DeepLinkRouter.shared.handle(URL(string: "bizarrecrm://tickets")!)
                }
                .keyboardShortcut("2", modifiers: .command)

                Button("Customers") {
                    DeepLinkRouter.shared.handle(URL(string: "bizarrecrm://customers")!)
                }
                .keyboardShortcut("3", modifiers: .command)

                Button("POS Register") {
                    DeepLinkRouter.shared.handle(URL(string: "bizarrecrm://pos")!)
                }
                .keyboardShortcut("4", modifiers: .command)

                Divider()

                Button("Command Palette") {
                    DeepLinkRouter.shared.handle(URL(string: "bizarrecrm://command-palette")!)
                }
                .keyboardShortcut("k", modifiers: .command)

                Button("Keyboard Shortcuts") {
                    DeepLinkRouter.shared.handle(URL(string: "bizarrecrm://shortcuts")!)
                }
                .keyboardShortcut("/", modifiers: .command)
            }

            // Actions menu — quick actions
            CommandMenu("Actions") {
                Button("New Customer") {
                    DeepLinkRouter.shared.handle(URL(string: "bizarrecrm://customer/new")!)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Button("New Invoice") {
                    DeepLinkRouter.shared.handle(URL(string: "bizarrecrm://invoice/new")!)
                }

                Divider()

                Button("Print…") {
                    DeepLinkRouter.shared.handle(URL(string: "bizarrecrm://print")!)
                }
                .keyboardShortcut("p", modifiers: .command)
            }

            // Help menu — supplement system help
            CommandGroup(after: .help) {
                Button("BizarreCRM Help") {
                    if let url = URL(string: "https://help.bizarrecrm.com") {
                        #if canImport(UIKit)
                        UIApplication.shared.open(url)
                        #endif
                    }
                }
                .keyboardShortcut("?", modifiers: .command)
            }
        }

        // macOS-only sizing modifiers — on iOS they're ignored but their
        // presence in the scene graph can nudge SwiftUI into Mac-style sizing.
        #if os(macOS)
        return scene
            .defaultSize(width: 1200, height: 800)
            .windowResizability(.contentMinSize)
        #else
        return scene
        #endif
    }
}

// MARK: - Detail window (iPad multi-window / Stage Manager §22.4)

/// Secondary scene for opening entity details in independent iPad windows.
///
/// `MultiWindowCoordinator` calls `UIApplication.shared.requestSceneSessionActivation`
/// with an `NSUserActivity` whose `userInfo["deepLinkURL"]` encodes the route.
/// `SceneDelegate.scene(_:willConnectTo:options:)` picks this up and dispatches
/// to `HandoffReceiver` → `DeepLinkRouter`.
///
/// SwiftUI plumbing: declare this `WindowGroup` alongside the primary one so
/// the system can fulfil activation requests with `id: "detail"`.
///
/// Example (place directly after the closing `}` of the primary `WindowGroup`):
/// ```swift
/// WindowGroup(id: "detail", for: DeepLinkRoute.self) { $route in
///     DetailWindowScene(route: route)
///         .environment(appState)
///         .tint(.bizarreOrange)
///         .preferredColorScheme(appState.forcedColorScheme)
/// }
/// ```
///
/// Note: The `WindowGroup(id:for:)` initialiser requires iOS 16+; it is safe
/// to add it unconditionally since the iOS deployment target is 17.
// (Window group body intentionally documented above rather than declared here
//  to avoid requiring all feature-package Detail views at the App-target link
//  level.  Add the WindowGroup declaration to BizarreCRMApp.body once the
//  feature packages expose their detail views publicly.)
