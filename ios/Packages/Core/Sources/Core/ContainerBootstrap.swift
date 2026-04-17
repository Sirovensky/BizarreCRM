import Foundation
import Factory

/// Registers cross-feature defaults in the Factory container.
/// Each feature package extends `Container` with its own factories;
/// this entry point is a safe place for app-launch wiring.
public enum ContainerBootstrap {
    public static func registerDefaults() {
        AppLog.app.info("Factory container registered (app=\(Platform.appVersion) build=\(Platform.buildNumber))")
    }
}
