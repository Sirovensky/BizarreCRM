#if canImport(Darwin)
import Darwin
#endif
import Foundation

/// Lightweight resident-memory probe using the Mach task info API.
///
/// ## Swift 6 / Sendable
/// `MemoryProbe` is a `public enum` (no stored state) so it is implicitly
/// `Sendable` without any annotation.
///
/// ## macOS / Catalyst
/// The `mach_task_basic_info` family is available on all Apple Darwin
/// platforms via the `Darwin` module. The `#if canImport(Darwin)` guard
/// ensures the implementation compiles on non-Darwin targets (Linux CI)
/// without emitting an error.
///
/// ## Usage
/// ```swift
/// let mb = MemoryProbe.currentResidentMB()
/// MemoryProbe.sample(label: "after-sync")
/// ```
public enum MemoryProbe {

    // MARK: - Public API

    /// Returns the current resident set size of the process in megabytes.
    ///
    /// Uses `task_info(mach_task_self_, MACH_TASK_BASIC_INFO, ...)` to read
    /// `phys_footprint` (the memory-pressure-relevant footprint reported in
    /// Instruments → Allocations). Returns `0` on non-Darwin platforms.
    ///
    /// - Returns: Resident memory in MB, or `0` if the query fails.
    public static func currentResidentMB() -> Double {
#if canImport(Darwin)
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) { ptr in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), ptr, &count)
            }
        }

        guard result == KERN_SUCCESS else { return 0 }

        // `resident_size` is the virtual resident set size in bytes.
        // Divide by 1024^2 to convert bytes → MB.
        let bytes = Double(info.resident_size)
        return bytes / (1024.0 * 1024.0)
#else
        return 0
#endif
    }

    /// Samples current memory and logs via `AppLog.perf`.
    ///
    /// Each call emits one `info`-level log line:
    /// ```
    /// [MemoryProbe] <label>: 123.4 MB
    /// ```
    ///
    /// - Parameter label: A short identifier for this sample point (e.g. `"idle"`, `"after-sync"`).
    public static func sample(label: String) {
        let mb = currentResidentMB()
        AppLog.perf.info("[MemoryProbe] \(label, privacy: .public): \(String(format: "%.1f", mb), privacy: .public) MB")
    }
}
