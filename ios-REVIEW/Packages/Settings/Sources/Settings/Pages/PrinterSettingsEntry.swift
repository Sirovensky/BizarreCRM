import SwiftUI
import DesignSystem

/// §19 Phase 9 — Printer settings entry.
/// A NavigationLink that routes to the existing `PrinterSettingsView`
/// shipped in Phase 5A (Hardware package). We wrap it here so the
/// Settings package can include a list row without importing the full
/// Hardware package as a dependency. When the Hardware package is
/// linked (App target), pass `destination` at the call site.
public struct PrinterSettingsEntry<Destination: View>: View {
    let destination: Destination

    public init(@ViewBuilder destination: () -> Destination) {
        self.destination = destination()
    }

    public var body: some View {
        NavigationLink(destination: destination) {
            Label("Printer settings", systemImage: "printer")
                .accessibilityLabel("Printer settings")
        }
        .accessibilityIdentifier("settings.printerSettings")
    }
}

/// Fallback entry shown when no destination is provided — renders a
/// plain row that can be replaced once the Hardware package is linked.
public struct PrinterSettingsEntryPlaceholder: View {
    public init() {}

    public var body: some View {
        Label("Printer settings", systemImage: "printer")
            .foregroundStyle(.bizarreOnSurface)
            .accessibilityLabel("Printer settings — not yet configured")
            .accessibilityIdentifier("settings.printerSettingsPlaceholder")
    }
}
