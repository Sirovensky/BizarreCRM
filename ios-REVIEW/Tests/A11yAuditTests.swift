// ios/Tests/A11yAuditTests.swift
//
// XCTest harness that invokes a11y-audit.sh and asserts it exits cleanly.
// In regression-check mode the script fails only if violations increased vs
// baseline — this lets existing violations be tracked without blocking CI
// until the full retrofit is done (Phase 10 sprint).
//
// §29 Automated a11y audit CI

import XCTest

final class A11yAuditTests: XCTestCase {

    // MARK: - Script location

    private var scriptURL: URL {
        // Locate a11y-audit.sh relative to this test file at build time.
        // In CI the script is at ios/scripts/a11y-audit.sh from repo root.
        // XCTest bundles embed a __FILE__ path; we walk up to find the repo root.
        let thisFile = URL(fileURLWithPath: #file)
        // #file = .../ios/Tests/A11yAuditTests.swift
        // walk up: Tests → ios → repo root → ios/scripts/a11y-audit.sh
        let iosDir = thisFile
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // ios/
        return iosDir.appendingPathComponent("scripts/a11y-audit.sh")
    }

    private var iosDir: URL {
        URL(fileURLWithPath: #file)
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // ios/
    }

    // MARK: - Tests

    /// Verifies the script is present and executable.
    func test_scriptExists() throws {
        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(atPath: scriptURL.path),
                      "a11y-audit.sh must exist at \(scriptURL.path)")
        let attrs = try fm.attributesOfItem(atPath: scriptURL.path)
        let perms = attrs[.posixPermissions] as? Int ?? 0
        // Owner-execute bit (0o100)
        XCTAssertTrue(perms & 0o100 != 0, "a11y-audit.sh must be executable")
    }

    /// Runs a11y-audit.sh in regression-check mode.
    ///
    /// - Passes if violations ≤ baseline (no regressions introduced).
    /// - If no baseline exists yet, runs in full mode and expects 0 violations
    ///   (clean tree) or documents baseline automatically.
    func test_noA11yRegressions() throws {
        let baselinePath = iosDir.appendingPathComponent(".a11y-baseline.txt").path
        let fm = FileManager.default

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")

        if fm.fileExists(atPath: baselinePath) {
            // Regression mode: only fail if count increased.
            process.arguments = [
                scriptURL.path,
                "--check-regressions",
                "--search-root", iosDir.path,
            ]
        } else {
            // First run: write baseline and pass.
            process.arguments = [
                scriptURL.path,
                "--baseline",
                "--search-root", iosDir.path,
            ]
        }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError  = pipe

        try process.run()
        process.waitUntilExit()

        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""

        XCTAssertEqual(
            process.terminationStatus, 0,
            "a11y-audit.sh exited \(process.terminationStatus).\nOutput:\n\(output)"
        )
    }

    /// Verifies the JSON output is valid JSON with expected keys.
    func test_jsonOutputIsValid() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            scriptURL.path,
            "--json-only",
            "--search-root", iosDir.path,
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError  = Pipe() // discard stderr

        try process.run()
        process.waitUntilExit()

        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        let json = try JSONSerialization.jsonObject(with: outputData) as? [String: Any]
        XCTAssertNotNil(json, "Output must be valid JSON")
        XCTAssertNotNil(json?["violations_total"], "JSON must contain 'violations_total'")
        XCTAssertNotNil(json?["files_checked"],    "JSON must contain 'files_checked'")
        XCTAssertNotNil(json?["violations"],        "JSON must contain 'violations' array")

        let filesChecked = json?["files_checked"] as? Int ?? 0
        XCTAssertGreaterThan(filesChecked, 0, "Should have checked at least one Swift file")
    }
}
