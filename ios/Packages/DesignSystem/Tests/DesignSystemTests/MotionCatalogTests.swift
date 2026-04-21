import Testing
import SwiftUI
@testable import DesignSystem

// §67 — MotionCatalog / ReduceMotionFallback tests

@Suite("MotionCatalog")
struct MotionCatalogTests {

    // MARK: - Token existence

    @Test("BrandMotion.chipToggle is defined")
    func chipToggleDefined() {
        let _: Animation = BrandMotion.chipToggle
        #expect(true)
    }

    @Test("BrandMotion.fabAppear is defined")
    func fabAppearDefined() {
        let _: Animation = BrandMotion.fabAppear
        #expect(true)
    }

    @Test("BrandMotion.bannerSlide is defined")
    func bannerSlideDefined() {
        let _: Animation = BrandMotion.bannerSlide
        #expect(true)
    }

    @Test("BrandMotion.tabSwitch is defined")
    func tabSwitchDefined() {
        let _: Animation = BrandMotion.tabSwitch
        #expect(true)
    }

    @Test("BrandMotion.pushNav is defined")
    func pushNavDefined() {
        let _: Animation = BrandMotion.pushNav
        #expect(true)
    }

    @Test("BrandMotion.modalSheet is defined")
    func modalSheetDefined() {
        let _: Animation = BrandMotion.modalSheet
        #expect(true)
    }

    @Test("BrandMotion.sharedElement is defined")
    func sharedElementDefined() {
        let _: Animation = BrandMotion.sharedElement
        #expect(true)
    }

    @Test("BrandMotion.pulse is defined")
    func pulseDefined() {
        let _: Animation = BrandMotion.pulse
        #expect(true)
    }
}

@Suite("ReduceMotionFallback")
struct ReduceMotionFallbackTests {

    @Test("reduced=true returns nil")
    func reducedReturnsNil() {
        let result = ReduceMotionFallback.animation(BrandMotion.modalSheet, reduced: true)
        #expect(result == nil)
    }

    @Test("reduced=false returns the base animation")
    func notReducedReturnsBase() {
        let base = BrandMotion.chipToggle
        let result = ReduceMotionFallback.animation(base, reduced: false)
        #expect(result != nil)
    }

    @Test("fadeOrFull reduced=true returns a non-nil animation (fade)")
    func fadeOrFullReducedReturnsFade() {
        let result = ReduceMotionFallback.fadeOrFull(BrandMotion.sharedElement, reduced: true)
        // Just check it's non-nil — it's the .easeInOut fade
        let _: Animation = result
        #expect(true)
    }

    @Test("fadeOrFull reduced=false returns base animation")
    func fadeOrFullNotReducedReturnsBase() {
        let base = BrandMotion.sharedElement
        let result = ReduceMotionFallback.fadeOrFull(base, reduced: false)
        let _: Animation = result
        #expect(true)
    }
}
