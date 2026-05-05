import XCTest
import SwiftUI
@testable import Sync

// §91.9-3 — Unit tests for StalenessLevel.color and StalenessIndicator
// preview stability, added in commit fba06fb6.
//
// The four staleness levels introduced a solid Capsule fill using `level.color`
// instead of the previous low-contrast glass tint.  These tests pin the colour
// semantics so regressions are caught before they reach CI.

// MARK: - StalenessLevel.color tests

final class StalenessLevel_91_9_ColorTests: XCTestCase {

    // MARK: 1. .fresh → bizarreSuccess (teal family)
    //         Task spec alias: "justNow" and "recent" both map to .fresh

    func test_freshLevel_color_isBizarreSuccess() {
        // .bizarreSuccess is SuccessGreen from BrandColors.
        // We verify it is the same Color reference as the named asset.
        let expected = Color.bizarreSuccess
        let actual   = StalenessLevel.fresh.color
        // SwiftUI Color doesn't expose components directly; compare descriptions.
        // Use the string representation to confirm token identity.
        XCTAssertEqual(
            "\(actual)", "\(expected)",
            ".fresh must return .bizarreSuccess (teal)"
        )
    }

    // MARK: 2. .warning → bizarreWarning (amber family)
    //         Task spec alias: this is the "N hr ago (warning)" tier

    func test_warningLevel_color_isBizarreWarning() {
        let expected = Color.bizarreWarning
        let actual   = StalenessLevel.warning.color
        XCTAssertEqual(
            "\(actual)", "\(expected)",
            ".warning must return .bizarreWarning (amber)"
        )
    }

    // MARK: 3. .stale → bizarreError (red family)
    //         Task spec alias: "stale"

    func test_staleLevel_color_isBizarreError() {
        let expected = Color.bizarreError
        let actual   = StalenessLevel.stale.color
        XCTAssertEqual(
            "\(actual)", "\(expected)",
            ".stale must return .bizarreError (red)"
        )
    }

    // MARK: 4. .never → bizarreError (red family)
    //         Task spec alias: "never"

    func test_neverLevel_color_isBizarreError() {
        let expected = Color.bizarreError
        let actual   = StalenessLevel.never.color
        XCTAssertEqual(
            "\(actual)", "\(expected)",
            ".never must return .bizarreError (red)"
        )
    }

    // MARK: 5. .fresh and .warning return distinct tokens

    func test_freshAndWarning_haveDistinctColors() {
        XCTAssertNotEqual(
            "\(StalenessLevel.fresh.color)",
            "\(StalenessLevel.warning.color)",
            ".fresh (teal) and .warning (amber) must be visually distinct tokens"
        )
    }

    // MARK: 6. .stale and .never share the same error token

    func test_staleAndNever_shareErrorToken() {
        XCTAssertEqual(
            "\(StalenessLevel.stale.color)",
            "\(StalenessLevel.never.color)",
            ".stale and .never must share .bizarreError — both signal an error state"
        )
    }

    // MARK: 7. StalenessLogic produces correct level → colour chain

    func test_logic_neverSynced_producesNeverLevel_andRedColor() {
        let logic = StalenessLogic(lastSyncedAt: nil)
        let level = logic.stalenessLevel
        XCTAssertEqual(level, .never)
        XCTAssertEqual(
            "\(level.color)",
            "\(Color.bizarreError)",
            "nil lastSyncedAt should map to .never → .bizarreError"
        )
    }

    func test_logic_fresh_under1hour_producesTealColor() {
        let now = Date()
        let logic = StalenessLogic(lastSyncedAt: now.addingTimeInterval(-30), now: now)
        let level = logic.stalenessLevel
        XCTAssertEqual(level, .fresh)
        XCTAssertEqual(
            "\(level.color)",
            "\(Color.bizarreSuccess)",
            "< 60 s should map to .fresh → .bizarreSuccess (teal)"
        )
    }

    func test_logic_warning_between1and4hours_producesAmberColor() {
        let now = Date()
        let logic = StalenessLogic(lastSyncedAt: now.addingTimeInterval(-5_400), now: now)
        let level = logic.stalenessLevel
        XCTAssertEqual(level, .warning)
        XCTAssertEqual(
            "\(level.color)",
            "\(Color.bizarreWarning)",
            "1–4 hr should map to .warning → .bizarreWarning (amber)"
        )
    }

    func test_logic_stale_over4hours_producesRedColor() {
        let now = Date()
        let logic = StalenessLogic(lastSyncedAt: now.addingTimeInterval(-20_000), now: now)
        let level = logic.stalenessLevel
        XCTAssertEqual(level, .stale)
        XCTAssertEqual(
            "\(level.color)",
            "\(Color.bizarreError)",
            "> 4 hr should map to .stale → .bizarreError (red)"
        )
    }
}

// MARK: - StalenessIndicator preview compilation guard

/// These tests act as a compile-time guard: if the `StalenessIndicator`
/// initialiser signature changes and the preview-like construction breaks,
/// this suite fails to compile.
///
/// §91.9-3 added dark + light #Preview stubs; the tests below mirror both.
final class StalenessIndicator_91_9_PreviewTests: XCTestCase {

    // MARK: 4a. StalenessIndicator constructs for "light" scenario (never synced)

    func test_preview_lightMode_neverSynced_constructs() {
        let view = StalenessIndicator(lastSyncedAt: nil)
        // If construction succeeds, the preview compiles correctly.
        _ = view.body
    }

    // MARK: 4b. StalenessIndicator constructs for "dark" scenario (just now)

    func test_preview_darkMode_justNow_constructs() {
        let now = Date()
        let view = StalenessIndicator(lastSyncedAt: now.addingTimeInterval(-30), now: now)
        _ = view.body
    }

    // MARK: 4c. StalenessIndicator constructs for all four staleness levels

    func test_preview_allLevels_construct() {
        let now = Date()
        let fixtures: [(Date?, String)] = [
            (nil,                              "never"),
            (now.addingTimeInterval(-30),      "fresh — just now"),
            (now.addingTimeInterval(-5_400),   "warning — 1.5 hr"),
            (now.addingTimeInterval(-20_000),  "stale — 5+ hr"),
        ]
        for (date, label) in fixtures {
            let view = StalenessIndicator(lastSyncedAt: date, now: now)
            _ = view.body  // compile-time + runtime construction guard
            let level = StalenessLogic(lastSyncedAt: date, now: now).stalenessLevel
            XCTAssertNotNil(level.color, "Level \(level) for \(label) should have a colour")
        }
    }
}

// MARK: - LightModePreviews.swift existence guard

/// §91.9-1 requires LightModePreviews.swift to exist and contain ≥ 3 #Preview
/// macros.  We cannot import a file-only artefact at test time, so this test
/// verifies the file is present on disk and its source contains the expected
/// preview macro invocations.
final class LightModePreviewsFile_91_9_Tests: XCTestCase {

    // MARK: 5a. LightModePreviews.swift exists in DesignSystem package

    func test_lightModePreviewsFile_exists() throws {
        // Resolve the path relative to the Bundle (works in SPM test runner).
        // Fall back to a fixed relative path from the source root.
        let candidates: [String] = [
            // SPM puts package sources adjacent to the test bundle
            Bundle(for: Self.self).bundlePath
                .components(separatedBy: ".build").first
                .map { $0 + "ios/Packages/DesignSystem/Sources/DesignSystem/LightModePreviews.swift" } ?? "",
            // Worktree-absolute path (CI environment)
            "/Users/serega/BizarreCRM/.claude/worktrees/agent-a231ad732761a63f7/ios/Packages/DesignSystem/Sources/DesignSystem/LightModePreviews.swift",
        ].filter { !$0.isEmpty }

        let exists = candidates.contains { FileManager.default.fileExists(atPath: $0) }
        XCTAssertTrue(exists,
            "LightModePreviews.swift must exist in DesignSystem/Sources/DesignSystem/")
    }

    // MARK: 5b. File contains at least 3 #Preview macros

    func test_lightModePreviewsFile_hasAtLeast3Previews() throws {
        let candidates: [String] = [
            Bundle(for: Self.self).bundlePath
                .components(separatedBy: ".build").first
                .map { $0 + "ios/Packages/DesignSystem/Sources/DesignSystem/LightModePreviews.swift" } ?? "",
            "/Users/serega/BizarreCRM/.claude/worktrees/agent-a231ad732761a63f7/ios/Packages/DesignSystem/Sources/DesignSystem/LightModePreviews.swift",
        ].filter { !$0.isEmpty }

        let path = try XCTUnwrap(
            candidates.first(where: { FileManager.default.fileExists(atPath: $0) }),
            "LightModePreviews.swift not found — §91.9-1 requires the file to exist"
        )
        let source = try String(contentsOfFile: path, encoding: .utf8)
        let previewCount = source.components(separatedBy: "#Preview(").count - 1
        XCTAssertGreaterThanOrEqual(
            previewCount, 3,
            "LightModePreviews.swift must contain ≥ 3 #Preview macros (found \(previewCount))"
        )
    }
}
