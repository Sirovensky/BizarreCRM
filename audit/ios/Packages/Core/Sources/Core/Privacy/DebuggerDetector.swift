import Foundation
import os

// §28.11 Jailbreak / integrity — debugger detection
//
// Detecting an attached debugger via `sysctl(P_FLAG_TRACED)` is a well-known
// and widely documented technique. It is NOT a security boundary by itself —
// a determined attacker patches the check or loads the binary outside a
// debugger. The value here is:
//
//   1. Increasing the attacker's cost (they must actively bypass it).
//   2. Feeding the signal into the server-side risk score for the session.
//   3. Logging an audit entry so security operations can correlate unusual
//      sessions in production.
//
// We deliberately do NOT abort the process on detection — that harms
// developers and QA engineers more than attackers.
//
// RELEASE BUILDS: the check runs but the process never exits and the result
// is surfaced only via the server risk payload.
// DEBUG BUILDS: a console warning is emitted so engineers notice accidental
// test-device mismatches.

// MARK: - DebuggerDetector

/// §28.11 — Detects whether a debugger is attached to the current process.
///
/// Uses `sysctl` to read the `kinfo_proc.kp_proc.p_flag` field and check the
/// `P_TRACED` bit — the canonical technique for this on Darwin.
///
/// Usage:
/// ```swift
/// let isDebugged = DebuggerDetector.isDebuggerAttached
/// if isDebugged {
///     // Include in server risk payload — do NOT block UX.
///     session.riskFlags.insert(.debuggerAttached)
/// }
/// ```
public enum DebuggerDetector {

    // MARK: - Public API

    /// Returns `true` if a debugger is currently attached to this process.
    ///
    /// This value can change between calls (a debugger can attach after launch),
    /// so callers that need a persistent flag should read it once and cache it.
    ///
    /// Always returns `false` in the simulator to avoid noise in CI.
    public static var isDebuggerAttached: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return sysctlTracedFlag()
        #endif
    }

    // MARK: - Risk payload helper

    /// A serialisable summary of the debugger-detection result, suitable for
    /// inclusion in server audit logs or a session risk payload.
    public static var riskEntry: DebuggerRiskEntry {
        let attached = isDebuggerAttached
        if attached {
            AppLog.privacy.warning("DebuggerDetector: debugger attached to process")
        }
        return DebuggerRiskEntry(debuggerAttached: attached, timestamp: Date())
    }

    // MARK: - Implementation

    /// Reads `P_TRACED` from `kinfo_proc` via `sysctl(CTL_KERN, KERN_PROC, KERN_PROC_PID, ...)`.
    ///
    /// This is the same approach used by Apple's own sample code and is well-known
    /// in the security community. It works in the main process; does not work across
    /// process boundaries.
    private static func sysctlTracedFlag() -> Bool {
        var info = kinfo_proc()
        var infoSize = MemoryLayout<kinfo_proc>.stride

        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        let result = sysctl(&mib, UInt32(mib.count), &info, &infoSize, nil, 0)

        guard result == 0 else {
            AppLog.privacy.error("DebuggerDetector: sysctl failed errno=\(errno, privacy: .public)")
            return false
        }

        // P_TRACED is defined as 0x00000800 in <sys/proc.h>.
        let P_TRACED: Int32 = 0x00000800
        return (info.kp_proc.p_flag & P_TRACED) != 0
    }
}

// MARK: - DebuggerRiskEntry

/// Serialisable snapshot for inclusion in server-side risk payloads.
public struct DebuggerRiskEntry: Sendable, Codable {
    public let debuggerAttached: Bool
    public let timestamp: Date

    public init(debuggerAttached: Bool, timestamp: Date) {
        self.debuggerAttached = debuggerAttached
        self.timestamp = timestamp
    }
}

// MARK: - AppLog.privacy

private extension AppLog {
    static var privacy: Logger {
        Logger(subsystem: "com.bizarrecrm", category: "Privacy")
    }
}
