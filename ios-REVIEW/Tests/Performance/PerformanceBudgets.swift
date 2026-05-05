/// Performance budgets for BizarreCRM iOS.
///
/// All thresholds are validated by the accompanying XCTest suites.
/// Update this file when product requirements change — tests automatically
/// pick up the new values on the next run.
public enum PerformanceBudget {
    // MARK: - Frame rate

    /// Target 60 fps → each frame ≤ 16.67 ms; p95 must be under this value.
    public static let scrollFrameP95Ms: Double = 16.67

    // MARK: - Launch

    /// App cold-start must be < 1.5 s on iPhone SE 3 (the slowest supported device).
    public static let coldStartMs: Double = 1500

    /// Warm-start (app already in memory, brought to foreground) < 250 ms.
    public static let warmStartMs: Double = 250

    // MARK: - List render

    /// Time from tab-select to first row visible < 500 ms.
    public static let listRenderMs: Double = 500

    // MARK: - Memory

    /// Idle resident memory footprint < 200 MB.
    public static let idleMemoryMB: Double = 200

    // MARK: - Network

    /// Network request timeout — fail the request after 10 s.
    public static let requestTimeoutMs: Double = 10_000

    /// Show a progress indicator if the request takes longer than 500 ms.
    public static let progressShowMs: Double = 500
}
