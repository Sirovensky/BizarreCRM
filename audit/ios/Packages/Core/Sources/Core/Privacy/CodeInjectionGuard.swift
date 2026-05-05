import Foundation
import os

// §28.11 Jailbreak / integrity — code-injection guard
//
// Code injection on iOS takes two main forms:
//
//   1. Dynamic-library injection via DYLD_INSERT_LIBRARIES (sandbox blocks this
//      on stock devices; jailbreaks can bypass it).
//   2. Substrate / Frida hooking — a malicious dylib patches method IMP pointers
//      at runtime.
//
// We detect both by:
//   A. Checking DYLD_INSERT_LIBRARIES is absent or contains only Apple-signed libs.
//   B. Enumerating loaded images for known hooking frameworks (see JailbreakDetector
//      for the primary path — CodeInjectionGuard focuses on the method-hook angle).
//   C. Verifying that critical Objective-C method IMPs (e.g., URLSession send)
//      point into Apple-signed memory regions, not injected code.
//
// IMPORTANT: These are heuristics. A sophisticated attacker removes their own
// traces. The goal is to raise the bar and feed the server risk signal, not to
// achieve perfect detection.

// MARK: - InjectionSignal

/// A single detected injection indicator.
public struct InjectionSignal: Sendable {
    /// Short machine-readable ID safe for audit logs.
    public let id: String
    /// Description for internal tooling — never show to end users.
    public let detail: String
    /// Whether the signal is considered high-confidence.
    public let isHighConfidence: Bool
}

// MARK: - CodeInjectionGuard

/// §28.11 — Detects common code-injection vectors at runtime.
///
/// Call ``scan()`` once at cold start from a background Task. The result feeds
/// into the server-side session risk score via the audit payload.
///
/// Never abort the process based solely on this result — false positives exist
/// and that would harm legitimate users.
public struct CodeInjectionGuard: Sendable {

    public init() {}

    // MARK: - Public API

    /// Runs all injection-detection heuristics synchronously.
    ///
    /// - Returns: An array of ``InjectionSignal`` items that fired (empty = clean).
    public func scan() -> [InjectionSignal] {
        #if targetEnvironment(simulator)
        return []
        #else
        var signals: [InjectionSignal] = []
        signals += checkDyldEnvironment()
        signals += checkLoadedImages()
        signals += checkObjCHooks()
        if !signals.isEmpty {
            AppLog.privacy.warning(
                "CodeInjectionGuard: \(signals.count, privacy: .public) signal(s) detected"
            )
        } else {
            AppLog.privacy.debug("CodeInjectionGuard: clean")
        }
        return signals
        #endif
    }

    // MARK: - Checks

    /// Reads the `DYLD_INSERT_LIBRARIES` environment variable. On a stock sandboxed
    /// device this environment variable is stripped by the kernel before `main()`.
    /// Its presence indicates a sandbox escape or jailbreak tool.
    private func checkDyldEnvironment() -> [InjectionSignal] {
        guard let value = ProcessInfo.processInfo.environment["DYLD_INSERT_LIBRARIES"],
              !value.isEmpty else {
            return []
        }
        return [InjectionSignal(
            id: "dyld.insert_libraries",
            detail: "DYLD_INSERT_LIBRARIES is set (value length: \(value.count))",
            isHighConfidence: true
        )]
    }

    /// Walks `_dyld_image_count` for libraries associated with code-injection
    /// and dynamic hooking frameworks.
    ///
    /// Keeps a separate list from ``JailbreakDetector`` to allow independent
    /// enable/disable of each detector.
    private func checkLoadedImages() -> [InjectionSignal] {
        let suspects: [String] = [
            "FridaGadget",
            "frida-agent",
            "cynject",
            "libhooker",
            "SubstrateLoader",
            "MobileSubstrate",
            "CydiaSubstrate",
            "SSLKillSwitch2",
            "objc_payload",
            "AltStore",         // AltStore JIT dylib injection (not inherently malicious but noteworthy)
        ]

        var signals: [InjectionSignal] = []
        let count = _dyld_image_count()
        for i in 0 ..< count {
            guard let raw = _dyld_get_image_name(i) else { continue }
            let name = String(cString: raw)
            for suspect in suspects {
                if name.localizedCaseInsensitiveContains(suspect) {
                    signals.append(InjectionSignal(
                        id: "image.inject",
                        detail: "Suspicious image: \(name)",
                        isHighConfidence: true
                    ))
                    break
                }
            }
        }
        return signals
    }

    /// Checks whether selected Objective-C method IMPs point into Apple-signed
    /// system frameworks vs. arbitrary (potentially injected) memory.
    ///
    /// We inspect `URLSession.dataTask(with:completionHandler:)` because it is
    /// a common hooking target for traffic interception.
    ///
    /// Implementation note: `class_getMethodImplementation` returns a function
    /// pointer. We compare its address against known Apple framework regions
    /// using `_dyld_get_image_vmaddr_slide` — if the IMP lives outside every
    /// known Apple image range we flag it.
    ///
    /// This check fires only if there is *no* matching framework range for the
    /// IMP address (i.e., it lives in a gap not covered by any loaded image),
    /// which strongly suggests a runtime patch.
    private func checkObjCHooks() -> [InjectionSignal] {
        #if canImport(ObjectiveC)
        // Selector to inspect: -[NSURLSession dataTaskWithRequest:completionHandler:]
        let cls: AnyClass? = NSClassFromString("NSURLSession")
        guard let cls else { return [] }

        let sel = NSSelectorFromString("dataTaskWithRequest:completionHandler:")
        guard let imp = class_getMethodImplementation(cls, sel) else { return [] }
        let impAddress = unsafeBitCast(imp, to: UnsafeRawPointer.self)

        // Build a list of [start, end) ranges for every loaded dylib.
        let imageCount = _dyld_image_count()
        for i in 0 ..< imageCount {
            guard let header = _dyld_get_image_header(i),
                  let name = _dyld_get_image_name(i) else { continue }

            // Only trust Apple-signed frameworks under /usr/lib or /System.
            let imageName = String(cString: name)
            guard imageName.hasPrefix("/usr/lib/") || imageName.hasPrefix("/System/") else { continue }

            let slide = _dyld_get_image_vmaddr_slide(i)
            // Map the mach_header to an approximate range.
            // We check if the IMP pointer falls within 64 MB of the image base —
            // a coarse but effective check given Apple frameworks are compact.
            let base = UnsafeRawPointer(header)
            let rangeEnd = base.advanced(by: 64 * 1024 * 1024)
            _ = slide // slide incorporated via header pointer which already accounts for ASLR

            if impAddress >= base && impAddress < rangeEnd {
                // IMP is within a known Apple framework — this is expected.
                return []
            }
        }

        // IMP was not found in any Apple framework range.
        return [InjectionSignal(
            id: "objc.hook",
            detail: "NSURLSession IMP outside Apple framework range",
            isHighConfidence: true
        )]
        #else
        return []
        #endif
    }
}

// MARK: - AppLog.privacy

private extension AppLog {
    static var privacy: Logger {
        Logger(subsystem: "com.bizarrecrm", category: "Privacy")
    }
}
