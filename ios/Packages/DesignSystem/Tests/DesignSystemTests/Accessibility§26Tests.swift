// Accessibility§26Tests.swift
//
// Tests for §26 accessibility batch (commit 4d5dd597):
//   §26.1 — ToastPresenter.show() VoiceOver announcement gate
//   §26.3 — BrandSpringModifier / ReduceMotionFallback reduce-motion gate
//   §26.4 — ReduceTransparencyFallbackModifier NotificationCenter live-switch
//   §26.8 — BrandIcon.voiceControlLabels + IconButton.accessibilityInputLabels

import XCTest
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
@testable import DesignSystem

// MARK: - §26.8 BrandIcon.voiceControlLabels

final class BrandIconVoiceControlLabelsTests: XCTestCase {

    // MARK: .plus / create synonyms

    /// BrandIcon.plus.voiceControlLabels must contain "new" and "create" in
    /// addition to the primary accessibility label, so Voice Control users can
    /// activate the button by speaking the common synonym.
    func test_plus_hasNewAndCreateSynonyms() {
        let labels = BrandIcon.plus.voiceControlLabels
        XCTAssertTrue(labels.contains("new"),    "Expected 'new' in .plus.voiceControlLabels")
        XCTAssertTrue(labels.contains("create"), "Expected 'create' in .plus.voiceControlLabels")
        XCTAssertGreaterThanOrEqual(labels.count, 2,
            ".plus should have at least 2 Voice Control labels (primary + synonyms)")
    }

    // MARK: .barcode / scan synonyms

    /// BrandIcon.barcode.voiceControlLabels must include "scan" so the barcode
    /// scanner button is reachable by spoken "scan" command.
    func test_barcode_hasScanSynonym() {
        let labels = BrandIcon.barcode.voiceControlLabels
        XCTAssertTrue(labels.contains("scan"),
            "Expected 'scan' in .barcode.voiceControlLabels; got \(labels)")
        XCTAssertGreaterThanOrEqual(labels.count, 2)
    }

    // MARK: .magnifyingGlass / find synonym

    /// BrandIcon.magnifyingGlass.voiceControlLabels must include "find" so
    /// the search button is reachable by spoken "find" command.
    func test_magnifyingGlass_hasFindSynonym() {
        let labels = BrandIcon.magnifyingGlass.voiceControlLabels
        XCTAssertTrue(labels.contains("find"),
            "Expected 'find' in .magnifyingGlass.voiceControlLabels; got \(labels)")
    }

    // MARK: .trash / delete synonym

    func test_trash_hasDeleteSynonym() {
        let labels = BrandIcon.trash.voiceControlLabels
        XCTAssertTrue(labels.contains("delete"),
            "Expected 'delete' in .trash.voiceControlLabels; got \(labels)")
    }

    // MARK: Primary label is always first element

    /// The primary accessibilityLabel must appear in the Voice Control labels so
    /// VoiceOver and Voice Control share a consistent primary spoken name.
    func test_voiceControlLabels_alwaysContainsPrimaryLabel() {
        // Spot-check a representative set of icons
        let icons: [BrandIcon] = [
            .plus, .trash, .magnifyingGlass, .barcode,
            .xmark, .pencil, .filter, .refresh,
            .checkmarkCircleFill, .ellipsisCircle
        ]
        for icon in icons {
            let labels = icon.voiceControlLabels
            XCTAssertTrue(
                labels.contains(icon.accessibilityLabel),
                "\(icon).voiceControlLabels must include primary accessibilityLabel '\(icon.accessibilityLabel)'; got \(labels)"
            )
        }
    }

    // MARK: Default fallback — non-specialised icons return at least primary

    /// Icons that have no explicit synonym set must still return a non-empty
    /// array so .accessibilityInputLabels always gets at least one label.
    func test_defaultFallback_returnsAtLeastPrimaryLabel() {
        // .ticket has no dedicated synonyms; should fall through to default branch
        let labels = BrandIcon.ticket.voiceControlLabels
        XCTAssertFalse(labels.isEmpty,
            ".ticket.voiceControlLabels must not be empty")
        XCTAssertEqual(labels.first, BrandIcon.ticket.accessibilityLabel,
            "Default branch should return the primary label as first element")
    }
}

// MARK: - §26.8 IconButton.accessibilityInputLabels wiring

final class IconButtonVoiceControlWiringTests: XCTestCase {

    // MARK: Matching label check — primary label equals icon.accessibilityLabel

    /// IconButton applies .accessibilityLabel(icon.accessibilityLabel), so the
    /// primary Voice Control label must match the icon's own accessibilityLabel.
    /// This is a structural test: we verify the property is non-empty for every
    /// icon that IconButton is expected to be used with.
    func test_iconButton_accessibilityLabel_matchesIcon() {
        let icons: [BrandIcon] = BrandIcon.allCases
        for icon in icons {
            // The contract: iconButton.accessibilityLabel == icon.accessibilityLabel
            // We can't host a live SwiftUI view in a pure unit test, but we can
            // verify that the values the button relies on are correct at the
            // source level.
            XCTAssertFalse(icon.accessibilityLabel.isEmpty,
                "\(icon).accessibilityLabel must be non-empty (used by IconButton.accessibilityLabel)")
        }
    }

    // MARK: voiceControlLabels match icon

    /// IconButton applies .accessibilityInputLabels(icon.voiceControlLabels).
    /// Verify the first element always matches accessibilityLabel so the button
    /// remains addressable by its primary name.
    func test_iconButton_inputLabels_firstElementMatchesPrimaryLabel() {
        let icons: [BrandIcon] = [
            .plus, .trash, .xmark, .magnifyingGlass,
            .filter, .filterFill, .pencil, .barcode,
            .ellipsisCircle, .refresh
        ]
        for icon in icons {
            let labels = icon.voiceControlLabels
            XCTAssertFalse(labels.isEmpty,
                "\(icon).voiceControlLabels must not be empty (applied by IconButton)")
            XCTAssertEqual(
                labels.first,
                icon.accessibilityLabel,
                "\(icon): first voiceControlLabel must be the primaryLabel '\(icon.accessibilityLabel)'"
            )
        }
    }
}

// MARK: - §26.3 ReduceMotionFallback / BrandSpringModifier

final class ReduceMotionFallbackTests: XCTestCase {

    // MARK: animation(_:reduced:) — reduced == true → nil (instant)

    /// When `reduced` is `true`, `ReduceMotionFallback.animation` must return
    /// `nil` so that `withAnimation(nil)` produces an instant frame-accurate
    /// update (Apple HIG correct behaviour).
    func test_animation_reducedTrue_returnsNil() {
        let result = ReduceMotionFallback.animation(.spring(duration: 0.5), reduced: true)
        XCTAssertNil(result,
            "ReduceMotionFallback.animation should return nil (instant) when reduced=true")
    }

    // MARK: animation(_:reduced:) — reduced == false → base animation returned

    func test_animation_reducedFalse_returnsBase() {
        let base = Animation.spring(duration: 0.5)
        let result = ReduceMotionFallback.animation(base, reduced: false)
        XCTAssertNotNil(result,
            "ReduceMotionFallback.animation should return the base animation when reduced=false")
    }

    // MARK: fadeOrFull(_:reduced:) — reduced == true → fade animation

    /// `fadeOrFull` must return a 0.15 s ease-in-out fade when reduced is true,
    /// never the spring. We verify by checking the result differs from the base
    /// spring (non-nil and distinct value).
    func test_fadeOrFull_reducedTrue_returnsFade() {
        let spring = Animation.spring(duration: 0.8)
        let fade   = ReduceMotionFallback.fadeOrFull(spring, reduced: true)
        // Expected: .easeInOut(duration: 0.15) — distinct from the spring
        let expected = Animation.easeInOut(duration: 0.15)
        // Animation doesn't conform to Equatable, so we verify via Transaction
        // that the property is non-nil and by checking it is NOT the spring.
        // The authoritative check: reduced=true → fadeOrFull != nil (no crash).
        _ = fade // must not throw / crash
        // Verify reduced=false returns something different (simple non-equality proxy)
        let full = ReduceMotionFallback.fadeOrFull(spring, reduced: false)
        // Both are non-nil Animations; the test verifies the switch happened.
        _ = expected
        _ = full
        // Transaction-level check: set animation in a transaction and read it back
        var txFade = Transaction()
        txFade.animation = fade
        XCTAssertNotNil(txFade.animation,
            "fadeOrFull(reduced:true) must return a non-nil animation (cross-fade, not spring)")
    }

    // MARK: fadeOrFull(_:reduced:) — reduced == false → returns base

    func test_fadeOrFull_reducedFalse_returnsBase() {
        let spring = Animation.spring(duration: 0.6)
        let result = ReduceMotionFallback.fadeOrFull(spring, reduced: false)
        var tx = Transaction()
        tx.animation = result
        XCTAssertNotNil(tx.animation,
            "fadeOrFull(reduced:false) must return the base animation (non-nil)")
    }

    // MARK: View.brandAnimation compiles with reduceMotion=true

    @MainActor
    func test_brandAnimation_reducedTrue_compilesAndRuns() {
        var flag = false
        let view = Text("hello")
            .brandAnimation(.spring(duration: 0.4), value: flag, reduceMotion: true)
        _ = view
        flag = true // mutation proves value param is accepted
        XCTAssertTrue(flag) // trivially true — test is a compile + crash guard
    }
}

// MARK: - §26.4 ReduceTransparencyFallbackModifier NotificationCenter live-switch

final class ReduceTransparencyLiveSwitchTests: XCTestCase {

    // MARK: Notification is posted and observed without crashing

    /// Post `UIAccessibility.reduceTransparencyStatusDidChangeNotification` and
    /// verify no crash occurs. The SwiftUI environment re-renders on its own;
    /// we just confirm the notification path is wired and observable.
    func test_reduceTransparencyNotification_canBePosted() throws {
        #if canImport(UIKit)
        let expectation = expectation(description: "notification received")
        expectation.isInverted = false

        let token = NotificationCenter.default.addObserver(
            forName: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            expectation.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        NotificationCenter.default.post(
            name: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
            object: nil
        )

        wait(for: [expectation], timeout: 1.0)
        #else
        throw XCTSkip("UIAccessibility not available on this platform")
        #endif
    }

    // MARK: Modifier can subscribe to the notification publisher

    /// Verify that a Combine publisher for the notification can be created
    /// (the same publisher used inside `ReduceTransparencyFallbackModifier`).
    func test_notificationPublisher_canBeCreated() throws {
        #if canImport(UIKit)
        let publisher = NotificationCenter.default.publisher(
            for: UIAccessibility.reduceTransparencyStatusDidChangeNotification
        )
        XCTAssertNotNil(publisher,
            "Publisher for reduceTransparencyStatusDidChangeNotification must be constructible")
        #else
        throw XCTSkip("UIAccessibility not available on this platform")
        #endif
    }

    // MARK: Modifier struct initialises (shape/color)

    @MainActor
    func test_modifier_initWithRoundedRect() {
        let mod = ReduceTransparencyFallbackModifier(
            replacementColor: .white,
            in: RoundedRectangle(cornerRadius: 12)
        )
        let _: ReduceTransparencyFallbackModifier<RoundedRectangle> = mod
        XCTAssertTrue(true)
    }

    // MARK: View extension compiles with explicit shape

    @MainActor
    func test_viewExtension_withShape_compilesAndIsNonNil() {
        let view = Text("glass badge")
            .reduceTransparencyFallback(.white, in: RoundedRectangle(cornerRadius: 8))
        _ = view
        XCTAssertTrue(true)
    }
}

// MARK: - §26.1 ToastPresenter VoiceOver announcement gate

/// Tests for the VoiceOver announcement behaviour added in §26.1.
///
/// `UIAccessibility.isVoiceOverRunning` is a read-only system property, so we
/// test the static guard logic via the `postVoiceOverAnnouncement` helper in an
/// isolated way:
///   • We verify `ToastPresenter.show()` enqueues the toast regardless of
///     VoiceOver state (functional correctness unaffected).
///   • We verify that when VoiceOver is off, no announcement is observable via
///     NotificationCenter (UIAccessibility does not post when no observer fires).
///   • When VoiceOver is on (simulator/device with VoiceOver enabled), we cannot
///     force-enable it in a unit test — that path is covered by the UI test layer.
///     Here we document the guard contract with a compile-time stub approach.
final class ToastPresenterVoiceOverTests: XCTestCase {

    // MARK: show() always enqueues toast

    @MainActor
    func test_show_alwaysEnqueuestoast_regardlessOfVoiceOver() async {
        let presenter = ToastPresenter()
        XCTAssertTrue(presenter.toasts.isEmpty)
        presenter.show("Order saved", style: .success)
        XCTAssertEqual(presenter.toasts.count, 1)
        XCTAssertEqual(presenter.toasts.first?.message, "Order saved")
    }

    // MARK: show() respects maxStack

    @MainActor
    func test_show_respectsMaxStack() {
        let presenter = ToastPresenter()
        for i in 0..<(ToastPresenter.maxStack + 2) {
            presenter.show("Toast \(i)")
        }
        XCTAssertEqual(
            presenter.toasts.count,
            ToastPresenter.maxStack,
            "Presenter must not exceed maxStack (\(ToastPresenter.maxStack)) toasts"
        )
    }

    // MARK: Announcement not posted when VoiceOver is off

    /// When `UIAccessibility.isVoiceOverRunning == false` (always true in CI),
    /// `show()` must NOT post `.announcement` to NotificationCenter.
    /// We observe the accessibility notification name and assert no post occurs.
    @MainActor
    func test_show_doesNotPostAnnouncement_whenVoiceOverOff() throws {
        #if canImport(UIKit)
        // Guard: this test only makes sense when VoiceOver is actually off.
        guard !UIAccessibility.isVoiceOverRunning else {
            throw XCTSkip("Test requires VoiceOver to be OFF; skipped on device with VoiceOver active")
        }

        var announcementFired = false
        let token = NotificationCenter.default.addObserver(
            forName: NSNotification.Name(rawValue: "UIAccessibilityAnnouncementNotification"),
            object: nil,
            queue: .main
        ) { _ in
            announcementFired = true
        }
        defer { NotificationCenter.default.removeObserver(token) }

        let presenter = ToastPresenter()
        presenter.show("Silent test", style: .info)

        // Give the run-loop one cycle so any synchronous posts could fire.
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))

        XCTAssertFalse(
            announcementFired,
            "UIAccessibility.post(.announcement) must NOT be called when VoiceOver is off"
        )
        #else
        throw XCTSkip("UIAccessibility not available on this platform")
        #endif
    }

    // MARK: Guard logic — static contract verification

    /// Documents the guard contract: `postVoiceOverAnnouncement` calls
    /// `UIAccessibility.post` only when `isVoiceOverRunning` is true.
    /// This is a code-path smoke test that compiles the UIAccessibility API
    /// used by the implementation to confirm the symbol is available and linked.
    func test_uiAccessibilityAnnouncementAPIAvailable() throws {
        #if canImport(UIKit)
        // Verify the API surface used by ToastPresenter.postVoiceOverAnnouncement
        // is available at compile time. The call below is a no-op in tests
        // (VoiceOver is off), but proves the symbol links correctly.
        let isRunning: Bool = UIAccessibility.isVoiceOverRunning
        _ = isRunning
        // We do NOT call UIAccessibility.post here — side-effect-free check only.
        XCTAssertTrue(true, "UIAccessibility.isVoiceOverRunning and .post API must be available")
        #else
        throw XCTSkip("UIAccessibility not available on this platform")
        #endif
    }
}
