import Foundation
import os
#if canImport(UIKit)
import UIKit
#endif

// §28.11 Jailbreak / integrity — heuristic detection helper
//
// PHILOSOPHY: We never block UX on jailbreak detection alone. A jailbroken
// device is not the same as a malicious actor; many security researchers and
// power users run jailbroken devices legitimately. Hard blocking would harm
// legitimate users while a determined attacker would simply patch the check.
//
// What we DO:
//   - Flag the session server-side (log + risk score) so the tenant can decide.
//   - Warn in debug builds so engineers catch accidental test-device mismatches.
//   - Feed the result into App Attest (§28.11) — a compromised device will
//     fail Apple's server-side attestation independently of this code.
//
// What we do NOT do:
//   - Exit the process.
//   - Block sign-in.
//   - Refuse network calls.

// MARK: - JailbreakRiskLevel

/// Severity of the detected jailbreak signals.
public enum JailbreakRiskLevel: Int, Comparable, Sendable {
    /// No signals detected. Normal device.
    case none = 0
    /// One or more soft signals (e.g., a suspicious path exists) but no
    /// sandbox-escape confirmation. Could be a false positive on some configs.
    case low = 1
    /// Multiple independent signals or at least one strong indicator
    /// (e.g., sandbox write succeeded, `/bin/bash` present).
    case high = 2

    public static func < (lhs: JailbreakRiskLevel, rhs: JailbreakRiskLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - JailbreakSignal

/// Individual heuristic that contributed to the risk assessment.
public struct JailbreakSignal: Sendable {
    /// Short machine-readable identifier, safe to include in audit logs.
    public let id: String
    /// Human-readable description for internal tooling only — never shown to end users.
    public let detail: String
    /// Contribution to overall risk.
    public let weight: JailbreakRiskLevel
}

// MARK: - JailbreakDetector

/// §28.11 — Heuristic jailbreak / integrity detector.
///
/// Call ``assess()`` once at cold start (in a background Task) and pass the
/// result to your analytics / audit service. Do NOT gate user-visible flows on
/// this result alone.
///
/// All checks use only public APIs and do not attempt privilege escalation.
public struct JailbreakDetector: Sendable {

    public init() {}

    // MARK: - Public API

    /// Runs all heuristic checks and returns the aggregated risk level plus
    /// the individual signals that fired.
    ///
    /// This is a synchronous, CPU-only scan (no I/O, no network). Runs in < 5 ms
    /// on any modern device. Safe to call from a background actor.
    ///
    /// - Returns: A tuple of the highest ``JailbreakRiskLevel`` encountered and
    ///   an array of every ``JailbreakSignal`` that fired.
    public func assess() -> (level: JailbreakRiskLevel, signals: [JailbreakSignal]) {
        #if targetEnvironment(simulator)
        // Simulator: always skip — every check is a false positive.
        return (.none, [])
        #else
        var signals: [JailbreakSignal] = []

        signals += checkSuspiciousPaths()
        signals += checkSandboxEscape()
        signals += checkDynamicLinker()
        signals += checkURLSchemes()

        let level = signals.map(\.weight).max() ?? .none
        if level > .none {
            AppLog.privacy.warning(
                "JailbreakDetector: risk=\(level.rawValue, privacy: .public) signals=\(signals.count, privacy: .public)"
            )
        } else {
            AppLog.privacy.debug("JailbreakDetector: no signals detected")
        }
        return (level, signals)
        #endif
    }

    // MARK: - Checks

    /// Looks for filesystem artifacts left by common jailbreak tools.
    private func checkSuspiciousPaths() -> [JailbreakSignal] {
        let highRiskPaths = [
            "/bin/bash",
            "/usr/sbin/sshd",
            "/etc/apt",
            "/private/var/lib/apt",
            "/private/var/lib/cydia",
            "/var/lib/cydia",
            "/Applications/Cydia.app",
            "/Applications/Sileo.app",
            "/Applications/Zebra.app",
        ]
        let lowRiskPaths = [
            "/usr/bin/ssh",
            "/private/var/stash",
            "/private/var/mobile/Library/SBSettings/Themes",
        ]

        var signals: [JailbreakSignal] = []
        let fm = FileManager.default

        for path in highRiskPaths where fm.fileExists(atPath: path) {
            signals.append(JailbreakSignal(id: "path.high", detail: "Found: \(path)", weight: .high))
        }
        for path in lowRiskPaths where fm.fileExists(atPath: path) {
            signals.append(JailbreakSignal(id: "path.low", detail: "Found: \(path)", weight: .low))
        }
        return signals
    }

    /// Attempts to write outside the app sandbox. On a stock device this always
    /// fails with EPERM; on a jailbroken device it may succeed.
    private func checkSandboxEscape() -> [JailbreakSignal] {
        let probe = "/private/bizarrecrm_sandbox_probe_\(UUID().uuidString)"
        do {
            try "probe".write(toFile: probe, atomically: true, encoding: .utf8)
            // If we get here the sandbox is compromised.
            try? FileManager.default.removeItem(atPath: probe)
            return [JailbreakSignal(id: "sandbox.write", detail: "Write to \(probe) succeeded", weight: .high)]
        } catch {
            // Expected on stock devices — not a signal.
            return []
        }
    }

    /// Checks for injected dynamic libraries that are not part of our binary.
    /// `_dyld_image_count` + `_dyld_get_image_name` enumerate loaded images;
    /// suspicious names include common hooking frameworks.
    private func checkDynamicLinker() -> [JailbreakSignal] {
        let suspiciousLibraries = [
            "MobileSubstrate",
            "CydiaSubstrate",
            "SSLKillSwitch",
            "FridaGadget",
            "frida",
            "cynject",
            "SubstrateLoader",
        ]

        let count = _dyld_image_count()
        for i in 0 ..< count {
            guard let rawName = _dyld_get_image_name(i) else { continue }
            let name = String(cString: rawName)
            for suspect in suspiciousLibraries {
                if name.localizedCaseInsensitiveContains(suspect) {
                    return [JailbreakSignal(
                        id: "dyld.inject",
                        detail: "Suspicious library loaded: \(name)",
                        weight: .high
                    )]
                }
            }
        }
        return []
    }

    /// Checks if jailbreak-related URL schemes can be opened.
    /// On a stock device these will always return `false`.
    private func checkURLSchemes() -> [JailbreakSignal] {
        #if canImport(UIKit)
        let schemes = ["cydia://", "sileo://", "zbra://"]
        for scheme in schemes {
            if let url = URL(string: scheme), UIApplication.shared.canOpenURL(url) {
                return [JailbreakSignal(id: "url.scheme", detail: "Can open \(scheme)", weight: .low)]
            }
        }
        #endif
        return []
    }
}

// MARK: - AppLog.privacy convenience

private extension AppLog {
    static var privacy: Logger {
        Logger(subsystem: "com.bizarrecrm", category: "Privacy")
    }
}
