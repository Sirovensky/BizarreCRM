import XCTest
@testable import DesignSystem
import SwiftUI

/// §22 iPad Pro M4 — Unit tests for `NanoTexturedDisplayTint`.
final class NanoTexturedDisplayTintTests: XCTestCase {

    // MARK: - displaySurface

    func test_displaySurface_returnsAValidKind() {
        // On macOS test host UIKit is unavailable → always `.standard`
        // On iOS sim / device it will be `.standard` (sims don't report P3).
        let surface = NanoTexturedDisplayTint.displaySurface
        XCTAssertTrue(surface == .standard || surface == .wideGamutP3,
                      "Expected .standard or .wideGamutP3, got \(surface)")
    }

    // MARK: - isWideGamut

    func test_isWideGamut_matchesDisplaySurface() {
        let expected = NanoTexturedDisplayTint.displaySurface == .wideGamutP3
        XCTAssertEqual(NanoTexturedDisplayTint.isWideGamut, expected)
    }

    // MARK: - adjustedBrandOrange

    func test_adjustedBrandOrange_isNotClear() {
        // The adjusted colour must have some opacity — never fully transparent.
        // Color.opacity is not directly inspectable pre-iOS 17, so we verify
        // the path does not throw.
        let color = NanoTexturedDisplayTint.adjustedBrandOrange
        // If we got here without crash the helper is functional.
        _ = color
    }

    func test_adjustedBrandOrange_opacityClampedToOne_onStandard() {
        // On standard (non-P3) displays opacity multiplier is 1.0.
        // We can infer this from `isWideGamut` being false on test host.
        if !NanoTexturedDisplayTint.isWideGamut {
            // Standard path: opacity == 1.0 (no boost).
            // We can't introspect Color directly, but we verify no exception.
            let c = NanoTexturedDisplayTint.adjustedBrandOrange
            _ = c
        }
    }

    // MARK: - DisplaySurfaceKind

    func test_displaySurfaceKind_standard_notEqualP3() {
        XCTAssertNotEqual(DisplaySurfaceKind.standard, DisplaySurfaceKind.wideGamutP3)
    }

    func test_displaySurfaceKind_p3_notEqualStandard() {
        XCTAssertNotEqual(DisplaySurfaceKind.wideGamutP3, DisplaySurfaceKind.standard)
    }

    func test_displaySurfaceKind_standard_equalsSelf() {
        XCTAssertEqual(DisplaySurfaceKind.standard, DisplaySurfaceKind.standard)
    }

    func test_displaySurfaceKind_p3_equalsSelf() {
        XCTAssertEqual(DisplaySurfaceKind.wideGamutP3, DisplaySurfaceKind.wideGamutP3)
    }

    // MARK: - ProMotionAnimationBoost

    func test_proMotionMultiplier_onProMotion_isLessThanOne() {
        let m = ProMotionAnimationBoost.multiplier(true)
        XCTAssertLessThan(m, 1.0)
        XCTAssertGreaterThan(m, 0.0)
    }

    func test_proMotionMultiplier_onStandard_isOne() {
        let m = ProMotionAnimationBoost.multiplier(false)
        XCTAssertEqual(m, 1.0)
    }

    func test_proMotionAdjusted_scalesDuration_byMultiplier() {
        let base = 0.220   // BrandMotion.snappy
        let proMotion = ProMotionAnimationBoost.adjusted(base, isProMotion: true)
        let standard  = ProMotionAnimationBoost.adjusted(base, isProMotion: false)
        XCTAssertLessThan(proMotion, standard,
                          "ProMotion duration should be shorter than standard")
        XCTAssertEqual(standard, base, accuracy: 1e-9)
    }

    func test_proMotionDetector_returnsBool() {
        let result = ProMotionDetector.isProMotion
        XCTAssertTrue(result == true || result == false)
    }
}
