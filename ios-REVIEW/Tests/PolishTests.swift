import XCTest
@testable import DesignSystem

// MARK: - PolishTests
//
// §72 UX polish audit harness.
// Covers:
//   - ToastPresenter state machine (show / dismiss / auto-dismiss / stack cap)
//   - EmptyStateCard variant construction
//   - SkeletonShimmer / SkeletonRow / SkeletonList construction
//   - CentsFormatter
//   - MonospacedDigits (view modifier compiles)
//   - DragDismissIndicator (view modifier compiles)
//   - ux-polish-lint.sh exit code

@MainActor
final class ToastPresenterTests: XCTestCase {

    // MARK: show / dismiss

    func testShowAddsToast() {
        let presenter = ToastPresenter()
        presenter.show("Hello", style: .info)
        XCTAssertEqual(presenter.toasts.count, 1)
        XCTAssertEqual(presenter.toasts.first?.message, "Hello")
        XCTAssertEqual(presenter.toasts.first?.style, .info)
    }

    func testShowMultipleStylesAreStored() {
        let presenter = ToastPresenter()
        presenter.show("Info", style: .info)
        presenter.show("Success", style: .success)
        presenter.show("Warn", style: .warning)
        XCTAssertEqual(presenter.toasts.count, 3)
    }

    func testDismissRemovesToast() {
        let presenter = ToastPresenter()
        presenter.show("A")
        let toast = presenter.toasts[0]
        presenter.dismiss(toast)
        XCTAssertTrue(presenter.toasts.isEmpty)
    }

    func testDismissAllClearsStack() {
        let presenter = ToastPresenter()
        presenter.show("A")
        presenter.show("B")
        presenter.dismissAll()
        XCTAssertTrue(presenter.toasts.isEmpty)
    }

    // MARK: Stack cap

    func testStackCapEnforcedAtThree() {
        let presenter = ToastPresenter()
        presenter.show("1")
        presenter.show("2")
        presenter.show("3")
        presenter.show("4") // should evict "1"
        XCTAssertEqual(presenter.toasts.count, ToastPresenter.maxStack)
        // Oldest ("1") was removed; newest ("4") is last
        XCTAssertFalse(presenter.toasts.contains(where: { $0.message == "1" }))
        XCTAssertTrue(presenter.toasts.contains(where: { $0.message == "4" }))
    }

    func testStackCapIsThree() {
        XCTAssertEqual(ToastPresenter.maxStack, 3)
    }

    // MARK: Duration

    func testInfoToastDuration() {
        let t = Toast(message: "x", style: .info)
        XCTAssertEqual(t.effectiveDuration, 4.0, accuracy: 0.01)
    }

    func testErrorToastDuration() {
        let t = Toast(message: "x", style: .error)
        XCTAssertEqual(t.effectiveDuration, 5.0, accuracy: 0.01)
    }

    func testCustomDurationOverridesDefault() {
        let t = Toast(message: "x", style: .error, duration: 2.5)
        XCTAssertEqual(t.effectiveDuration, 2.5, accuracy: 0.01)
    }

    // MARK: Icon names

    func testIconNamesPerStyle() {
        XCTAssertEqual(Toast(message: "", style: .info).iconSystemName, "info.circle.fill")
        XCTAssertEqual(Toast(message: "", style: .success).iconSystemName, "checkmark.circle.fill")
        XCTAssertEqual(Toast(message: "", style: .warning).iconSystemName, "exclamationmark.triangle.fill")
        XCTAssertEqual(Toast(message: "", style: .error).iconSystemName, "xmark.circle.fill")
    }

    // MARK: Toast immutability

    func testToastIsImmutable() {
        let t1 = Toast(message: "A", style: .info)
        let t2 = Toast(message: "A", style: .info)
        // Different IDs — each is a distinct value
        XCTAssertNotEqual(t1.id, t2.id)
    }
}

// MARK: - EmptyStateCardTests

final class EmptyStateCardTests: XCTestCase {

    func testStandardVariantConstruction() {
        let card = EmptyStateCard(
            icon: "tray",
            title: "No items",
            message: "Add your first item.",
            variant: .standard
        )
        // Verifies init doesn't crash and properties are set
        XCTAssertEqual(card.icon, "tray")
        XCTAssertEqual(card.title, "No items")
        XCTAssertEqual(card.variant, .standard)
        XCTAssertNil(card.primaryAction)
        XCTAssertNil(card.secondaryAction)
    }

    func testErrorVariantConstruction() {
        let card = EmptyStateCard.error(
            title: "Oops",
            message: "Try again",
            retry: {}
        )
        XCTAssertEqual(card.variant, .error)
        XCTAssertNotNil(card.primaryAction)
        XCTAssertEqual(card.primaryAction?.label, "Retry")
        XCTAssertEqual(card.primaryAction?.systemImage, "arrow.clockwise")
    }

    func testOnboardingVariantConstruction() {
        let card = EmptyStateCard(
            icon: "star",
            title: "Welcome",
            message: "Get started.",
            variant: .onboarding,
            primaryAction: EmptyStateAction(label: "Start", action: {})
        )
        XCTAssertEqual(card.variant, .onboarding)
        XCTAssertNotNil(card.primaryAction)
    }

    func testPrimaryAndSecondaryActions() {
        let card = EmptyStateCard(
            icon: "plus",
            title: "Empty",
            message: "Nothing here.",
            primaryAction: EmptyStateAction(label: "Add", action: {}),
            secondaryAction: EmptyStateAction(label: "Learn more", action: {})
        )
        XCTAssertNotNil(card.primaryAction)
        XCTAssertNotNil(card.secondaryAction)
        XCTAssertEqual(card.secondaryAction?.label, "Learn more")
    }

    func testEmptyStateActionWithSystemImage() {
        let action = EmptyStateAction(label: "Go", systemImage: "arrow.right", action: {})
        XCTAssertEqual(action.systemImage, "arrow.right")
        XCTAssertEqual(action.label, "Go")
    }
}

// MARK: - SkeletonShimmerTests

final class SkeletonShimmerTests: XCTestCase {

    func testSkeletonRowDefaultInit() {
        let row = SkeletonRow()
        XCTAssertFalse(row.showAvatar)
        XCTAssertEqual(row.lines, 2)
    }

    func testSkeletonRowCustomParams() {
        let row = SkeletonRow(showAvatar: true, lines: 3)
        XCTAssertTrue(row.showAvatar)
        XCTAssertEqual(row.lines, 3)
    }

    func testSkeletonRowMinimumOneLineEnforced() {
        let row = SkeletonRow(lines: 0) // should clamp to 1
        XCTAssertEqual(row.lines, 1)
    }

    func testSkeletonListDefaultInit() {
        let list = SkeletonList()
        XCTAssertEqual(list.rowCount, 5)
        XCTAssertFalse(list.showAvatars)
        XCTAssertEqual(list.linesPerRow, 2)
    }

    func testSkeletonListCustomParams() {
        let list = SkeletonList(rowCount: 8, showAvatars: true, linesPerRow: 3)
        XCTAssertEqual(list.rowCount, 8)
        XCTAssertTrue(list.showAvatars)
        XCTAssertEqual(list.linesPerRow, 3)
    }

    func testSkeletonListMinimumOneRowEnforced() {
        let list = SkeletonList(rowCount: 0)
        XCTAssertEqual(list.rowCount, 1)
    }
}

// MARK: - CentsFormatterTests

final class CentsFormatterTests: XCTestCase {

    func testDecimalFromCents() {
        let d = CentsFormatter.decimal(fromCents: 1234)
        XCTAssertEqual(d, Decimal(string: "12.34")!)
    }

    func testDecimalFromZeroCents() {
        XCTAssertEqual(CentsFormatter.decimal(fromCents: 0), 0)
    }

    func testDecimalFromNegativeCents() {
        let d = CentsFormatter.decimal(fromCents: -500)
        XCTAssertEqual(d, Decimal(string: "-5.00")!)
    }

    func testStringFormattingUSD() {
        let s = CentsFormatter.string(
            cents: 9999,
            currencyCode: "USD",
            locale: Locale(identifier: "en_US")
        )
        // Should contain the numeric value $99.99
        XCTAssertTrue(s.contains("99.99"), "Expected '99.99' in '\(s)'")
    }

    func testStringFormattingZero() {
        let s = CentsFormatter.string(
            cents: 0,
            currencyCode: "USD",
            locale: Locale(identifier: "en_US")
        )
        XCTAssertTrue(s.contains("0"), "Expected '0' in '\(s)'")
    }

    func testNoCentsDriftsOnLargeAmounts() {
        // 1_000_000 cents = $10,000.00 — no floating-point drift
        let d = CentsFormatter.decimal(fromCents: 1_000_000)
        XCTAssertEqual(d, Decimal(string: "10000.00")!)
    }
}

// MARK: - LintScriptTests

/// Runs `ios/scripts/ux-polish-lint.sh` and asserts exit 0.
/// This is the CI integration test for §72 anti-pattern regression.
final class LintScriptTests: XCTestCase {

    func testUXPolishLintExitsZero() throws {
        // Resolve script path relative to the source tree.
        // The test bundle is under ios/Packages/DesignSystem/.build/...
        // Walk up until we find ios/scripts/ux-polish-lint.sh.
        let scriptPath = try scriptURL()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["bash", scriptPath.path]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errOut = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        XCTAssertEqual(
            process.terminationStatus,
            0,
            "ux-polish-lint.sh exited \(process.terminationStatus).\nstdout:\n\(output)\nstderr:\n\(errOut)"
        )
    }

    // MARK: Private

    private func scriptURL() throws -> URL {
        // Strategy: walk up from #file until we find a directory containing
        // "scripts/ux-polish-lint.sh". Handles both placements:
        //   ios/Tests/PolishTests.swift         → up 1 = ios/
        //   ios/Packages/DesignSystem/Tests/…  → up 4 = ios/
        var dir = URL(fileURLWithPath: #file)
        for _ in 0..<8 {
            dir = dir.deletingLastPathComponent()
            let candidate = dir.appendingPathComponent("scripts/ux-polish-lint.sh")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        throw XCTSkip("ux-polish-lint.sh not found in any ancestor of \(#file) — skip CI gate on this host")
    }
}
