import Foundation
import Core

// MARK: - CommandPaletteTelemetry

/// Lightweight adapter that fires `AnalyticsDispatcher` events for command
/// palette interactions.
///
/// Integration:
/// ```swift
/// let telemetry = CommandPaletteTelemetry()
///
/// // when the palette opens
/// telemetry.paletteOpened()
///
/// // when the user executes a command
/// telemetry.commandExecuted(id: "new-ticket")
/// ```
///
/// The type is a thin value type; `AnalyticsDispatcher.log` is fire-and-forget
/// (backed by `TelemetryBuffer` actor). No retained state is needed here.
///
/// Thread safety: all methods are safe to call from any isolation domain because
/// `AnalyticsDispatcher.log` is nonisolated and enqueues asynchronously.
public struct CommandPaletteTelemetry: Sendable {

    public init() {}

    // MARK: - Events

    /// Call when the command palette sheet/overlay becomes visible.
    public func paletteOpened() {
        AnalyticsDispatcher.log(.commandPaletteOpened)
    }

    /// Call immediately after a command is executed.
    ///
    /// - Parameter id: The `CommandAction.id` of the executed action.
    ///                 Must not contain PII (action IDs are structural identifiers).
    public func commandExecuted(id: String) {
        AnalyticsDispatcher.log(.commandExecuted(commandId: id))
    }

    /// Call when the user performs a text search in the palette.
    ///
    /// - Parameter resultCount: Number of results shown. The raw query text
    ///   is intentionally NOT logged to preserve privacy.
    public func searchPerformed(resultCount: Int) {
        AnalyticsDispatcher.log(.searchPerformed(resultCount: resultCount))
    }

    /// Call when the palette is dismissed without executing a command.
    ///
    /// Maps to a `formDiscarded` event using `"command_palette"` as the form name
    /// so it appears alongside other abandonment metrics in the analytics pipeline.
    public func paletteDismissedWithoutExecution() {
        AnalyticsDispatcher.log(.formDiscarded(formName: "command_palette"))
    }
}
