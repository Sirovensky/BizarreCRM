import SwiftUI

// §29.9 Instruments profile / §29.12 Telemetry perf — in-app debug overlay.
//
// `PerformanceDebugOverlay` is a DEBUG-only floating HUD that displays a live
// snapshot of key §29 metrics:
//
//   • Resident memory (MB)          — sampled via MemoryProbe
//   • Low Power Mode indicator      — LowPowerModeObserver
//   • Last measured operation       — most recent BudgetGuard check result
//
// The overlay is attached via a View modifier:
//
//   ContentView()
//       .performanceDebugOverlay()
//
// In RELEASE builds the modifier is a transparent no-op so there is zero
// production overhead.  The overlay is iOS-only (UIKit resident-memory API).

#if DEBUG

// MARK: - PerformanceOverlayModel

/// Observable model that drives the overlay. Updated on a 1-second timer.
@MainActor
@Observable
final class PerformanceOverlayModel {

    var memoryMB: Double = 0
    var isLowPowerMode: Bool = false
    var frameRateNote: String = ""

    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func refresh() {
        memoryMB = Double(currentResidentBytes()) / 1_048_576
        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    // Thin resident-set-size probe (duplicates MemoryProbe logic so this
    // file stays self-contained with no inter-module import requirement).
    private func currentResidentBytes() -> UInt64 {
#if canImport(Darwin)
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.resident_size : 0
#else
        return 0
#endif
    }
}

// MARK: - PerformanceDebugOverlay (view)

/// A small floating HUD pinned to the top-leading corner showing live §29
/// metrics.  Only compiled and shown in DEBUG builds.
struct PerformanceDebugOverlay: View {

    @State private var model = PerformanceOverlayModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(
                String(format: "%.1f MB", model.memoryMB),
                systemImage: "memorychip"
            )
            .foregroundStyle(model.memoryMB > 200 ? .red : .green)

            if model.isLowPowerMode {
                Label("Low Power", systemImage: "bolt.slash.fill")
                    .foregroundStyle(.yellow)
            }
        }
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .padding(6)
        .background(.black.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(8)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - View modifier

private struct PerformanceDebugOverlayModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.overlay(alignment: .topLeading) {
            PerformanceDebugOverlay()
        }
    }
}

public extension View {
    /// Attaches a live performance HUD in DEBUG builds.
    ///
    /// Shows resident memory and Low Power Mode state, sampled every second.
    /// Compiled out entirely in RELEASE builds — zero production cost.
    ///
    /// ```swift
    /// WindowGroup {
    ///     RootView()
    ///         .performanceDebugOverlay()
    /// }
    /// ```
    func performanceDebugOverlay() -> some View {
        modifier(PerformanceDebugOverlayModifier())
    }
}

#else   // RELEASE

public extension View {
    /// No-op in RELEASE builds. See DEBUG variant for full documentation.
    @_transparent
    func performanceDebugOverlay() -> some View { self }
}

#endif  // DEBUG
