import SwiftUI
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
        // §22.3 — iPad-specific grouped menu bar. CommandGroup / CommandMenu
        // entries appear in the top-of-screen menu bar when a hardware keyboard
        // is attached (Stage Manager, external keyboard). They are silently
        // ignored on iPhone and have no effect on iPad without a keyboard.
        .commands {
            // File — new entities and sync.
            CommandGroup(replacing: .newItem) {
                Button("New Ticket") {
                    DeepLinkRouter.shared.handle(URL(string: "bizarrecrm://ticket/new")!)
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("New Customer") {
                    DeepLinkRouter.shared.handle(URL(string: "bizarrecrm://customer/new")!)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Divider()

                Button("Sync Now") {
                    Task { @MainActor in await SyncManager.shared.syncNow() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }

            // Actions — quick domain operations matching KeyboardShortcutCatalog.
            CommandMenu("Actions") {
                Button("Command Palette") {
                    DeepLinkRouter.shared.handle(URL(string: "bizarrecrm://palette")!)
                }
                .keyboardShortcut("k", modifiers: .command)

                Divider()

                Button("Find…") {
                    DeepLinkRouter.shared.handle(URL(string: "bizarrecrm://search")!)
                }
                .keyboardShortcut("f", modifiers: .command)

                Button("Find Customer by Phone") {
                    DeepLinkRouter.shared.handle(URL(string: "bizarrecrm://search?filter=phone")!)
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            }

            // Navigate — ⌘1–⌘8 tab / rail shortcuts.
            CommandMenu("Navigate") {
                Button("Dashboard")    { DeepLinkRouter.shared.handle(URL(string: "bizarrecrm://dashboard")!) }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Tickets")      { DeepLinkRouter.shared.handle(URL(string: "bizarrecrm://tickets")!) }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Customers")    { DeepLinkRouter.shared.handle(URL(string: "bizarrecrm://customers")!) }
                    .keyboardShortcut("3", modifiers: .command)
                Button("POS")          { DeepLinkRouter.shared.handle(URL(string: "bizarrecrm://pos")!) }
                    .keyboardShortcut("4", modifiers: .command)
                Button("Inventory")    { DeepLinkRouter.shared.handle(URL(string: "bizarrecrm://inventory")!) }
                    .keyboardShortcut("5", modifiers: .command)
                Button("Appointments") { DeepLinkRouter.shared.handle(URL(string: "bizarrecrm://appointments")!) }
                    .keyboardShortcut("6", modifiers: .command)
                Button("Reports")      { DeepLinkRouter.shared.handle(URL(string: "bizarrecrm://reports")!) }
                    .keyboardShortcut("7", modifiers: .command)
                Button("Settings")     { DeepLinkRouter.shared.handle(URL(string: "bizarrecrm://settings")!) }
                    .keyboardShortcut("8", modifiers: .command)
            }

            // Help — shortcuts overlay.
            CommandGroup(replacing: .help) {
                Button("Keyboard Shortcuts") {
                    DeepLinkRouter.shared.handle(URL(string: "bizarrecrm://shortcuts")!)
                }
                .keyboardShortcut("/", modifiers: .command)
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
