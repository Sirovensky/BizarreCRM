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
        WindowGroup {
            RootView()
                .environment(appState)
                .tint(.bizarreOrange)
                .preferredColorScheme(appState.forcedColorScheme)
                .onOpenURL { url in
                    DeepLinkRouter.shared.handle(url)
                }
        }
        .defaultSize(width: 1200, height: 800)
        .windowResizability(.contentMinSize)
        .commands {
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
        }
    }
}
