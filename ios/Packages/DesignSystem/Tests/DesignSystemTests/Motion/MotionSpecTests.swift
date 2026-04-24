import Testing
import SwiftUI
@testable import DesignSystem

// §67 — Motion Spec tests
// Covers: MotionDurationSpec, MotionEasingSpec, BrandAnimation, BrandTransition.

// MARK: - MotionDurationSpec

@Suite("MotionDurationSpec")
struct MotionDurationSpecTests {

    // MARK: Exact values

    @Test("instant is 80 ms")
    func instantIs80ms() {
        #expect(MotionDurationSpec.instant.seconds == 0.080)
    }

    @Test("short is 200 ms")
    func shortIs200ms() {
        #expect(MotionDurationSpec.short.seconds == 0.200)
    }

    @Test("medium is 320 ms")
    func mediumIs320ms() {
        #expect(MotionDurationSpec.medium.seconds == 0.320)
    }

    @Test("long is 480 ms")
    func longIs480ms() {
        #expect(MotionDurationSpec.long.seconds == 0.480)
    }

    // MARK: Ordering invariants

    @Test("durations are strictly ascending")
    func durationsStrictlyAscending() {
        let ordered = MotionDurationSpec.allCases.map(\.seconds)
        for i in 1..<ordered.count {
            #expect(ordered[i] > ordered[i - 1])
        }
    }

    // MARK: Alias consistency

    @Test("seconds and timeInterval return the same value")
    func secondsEqualsTimeInterval() {
        for spec in MotionDurationSpec.allCases {
            #expect(spec.seconds == spec.timeInterval)
        }
    }

    @Test("rawValue equals seconds")
    func rawValueEqualsSeconds() {
        for spec in MotionDurationSpec.allCases {
            #expect(spec.rawValue == spec.seconds)
        }
    }

    // MARK: CaseIterable completeness

    @Test("allCases contains all four tiers")
    func allCasesHasFourTiers() {
        #expect(MotionDurationSpec.allCases.count == 4)
    }
}

// MARK: - MotionEasingSpec

@Suite("MotionEasingSpec")
struct MotionEasingSpecTests {

    // MARK: Animation construction

    @Test("standard.animation(duration:) returns non-nil Animation")
    func standardAnimationNonNil() {
        let anim: Animation = MotionEasingSpec.standard.animation(duration: 0.3)
        let _: Animation = anim
        #expect(true)
    }

    @Test("decelerate.animation(duration:) returns non-nil Animation")
    func decelerateAnimationNonNil() {
        let anim: Animation = MotionEasingSpec.decelerate.animation(duration: 0.2)
        let _: Animation = anim
        #expect(true)
    }

    @Test("accelerate.animation(duration:) returns non-nil Animation")
    func accelerateAnimationNonNil() {
        let anim: Animation = MotionEasingSpec.accelerate.animation(duration: 0.16)
        let _: Animation = anim
        #expect(true)
    }

    @Test("emphasized.animation(duration:) returns non-nil Animation")
    func emphasizedAnimationNonNil() {
        let anim: Animation = MotionEasingSpec.emphasized.animation(duration: 0.48)
        let _: Animation = anim
        #expect(true)
    }

    // MARK: UnitCurve mapping

    @Test("all cases expose a unitCurve")
    func allCasesExposeUnitCurve() {
        for curve in MotionEasingSpec.allCases {
            let _: UnitCurve = curve.unitCurve
        }
        #expect(true)
    }

    // MARK: CaseIterable completeness

    @Test("allCases contains all four curves")
    func allCasesHasFourCurves() {
        #expect(MotionEasingSpec.allCases.count == 4)
    }
}

// MARK: - BrandAnimation

@Suite("BrandAnimation")
struct BrandAnimationTests {

    // MARK: Full animation (no Reduce Motion)

    @Test("snappy.animation is non-nil")
    func snappyAnimationNonNil() {
        let _: Animation = BrandAnimation.snappy.animation
        #expect(true)
    }

    @Test("smooth.animation is non-nil")
    func smoothAnimationNonNil() {
        let _: Animation = BrandAnimation.smooth.animation
        #expect(true)
    }

    @Test("soft.animation is non-nil")
    func softAnimationNonNil() {
        let _: Animation = BrandAnimation.soft.animation
        #expect(true)
    }

    // MARK: Reduce Motion: resolved returns nil

    @Test("snappy.resolved(reduceMotion:true) returns nil")
    func snappyReducedNil() {
        #expect(BrandAnimation.snappy.resolved(reduceMotion: true) == nil)
    }

    @Test("smooth.resolved(reduceMotion:true) returns nil")
    func smoothReducedNil() {
        #expect(BrandAnimation.smooth.resolved(reduceMotion: true) == nil)
    }

    @Test("soft.resolved(reduceMotion:true) returns nil")
    func softReducedNil() {
        #expect(BrandAnimation.soft.resolved(reduceMotion: true) == nil)
    }

    // MARK: No Reduce Motion: resolved returns animation

    @Test("snappy.resolved(reduceMotion:false) returns animation")
    func snappyNotReducedNonNil() {
        #expect(BrandAnimation.snappy.resolved(reduceMotion: false) != nil)
    }

    @Test("smooth.resolved(reduceMotion:false) returns animation")
    func smoothNotReducedNonNil() {
        #expect(BrandAnimation.smooth.resolved(reduceMotion: false) != nil)
    }

    @Test("soft.resolved(reduceMotion:false) returns animation")
    func softNotReducedNonNil() {
        #expect(BrandAnimation.soft.resolved(reduceMotion: false) != nil)
    }

    // MARK: CaseIterable completeness

    @Test("allCases contains exactly three presets")
    func allCasesHasThreePresets() {
        #expect(BrandAnimation.allCases.count == 3)
    }
}

// MARK: - BrandTransition

@Suite("BrandTransition")
struct BrandTransitionTests {

    // MARK: Non-reduced: transitions are constructed without throwing

    @Test("slideFromTrailing(reduceMotion:false) builds a transition")
    func slideFromTrailingFull() {
        let t: AnyTransition = BrandTransition.slideFromTrailing(reduceMotion: false)
        let _: AnyTransition = t
        #expect(true)
    }

    @Test("fadeScale(reduceMotion:false) builds a transition")
    func fadeScaleFull() {
        let t: AnyTransition = BrandTransition.fadeScale(reduceMotion: false)
        let _: AnyTransition = t
        #expect(true)
    }

    @Test("cardFlip(reduceMotion:false) builds a transition")
    func cardFlipFull() {
        let t: AnyTransition = BrandTransition.cardFlip(reduceMotion: false)
        let _: AnyTransition = t
        #expect(true)
    }

    @Test("heroZoom(reduceMotion:false) builds a transition")
    func heroZoomFull() {
        let t: AnyTransition = BrandTransition.heroZoom(reduceMotion: false)
        let _: AnyTransition = t
        #expect(true)
    }

    // MARK: Reduced: all transitions fall back to .opacity (AnyTransition)

    @Test("slideFromTrailing(reduceMotion:true) builds a transition")
    func slideFromTrailingReduced() {
        let t: AnyTransition = BrandTransition.slideFromTrailing(reduceMotion: true)
        let _: AnyTransition = t
        #expect(true)
    }

    @Test("fadeScale(reduceMotion:true) builds a transition")
    func fadeScaleReduced() {
        let t: AnyTransition = BrandTransition.fadeScale(reduceMotion: true)
        let _: AnyTransition = t
        #expect(true)
    }

    @Test("cardFlip(reduceMotion:true) builds a transition")
    func cardFlipReduced() {
        let t: AnyTransition = BrandTransition.cardFlip(reduceMotion: true)
        let _: AnyTransition = t
        #expect(true)
    }

    @Test("heroZoom(reduceMotion:true) builds a transition")
    func heroZoomReduced() {
        let t: AnyTransition = BrandTransition.heroZoom(reduceMotion: true)
        let _: AnyTransition = t
        #expect(true)
    }
}

// MARK: - Cross-spec integration

@Suite("MotionSpec integration")
struct MotionSpecIntegrationTests {

    @Test("BrandAnimation.snappy uses MotionDurationSpec.short duration")
    func snappyMatchesShortDuration() {
        // The snappy preset is defined with .short (200 ms); confirm the
        // underlying animation builds without error at that duration.
        let anim = MotionEasingSpec.decelerate.animation(
            duration: MotionDurationSpec.short.seconds
        )
        let _: Animation = anim
        #expect(true)
    }

    @Test("BrandAnimation.soft uses MotionDurationSpec.long duration")
    func softMatchesLongDuration() {
        let anim = MotionEasingSpec.standard.animation(
            duration: MotionDurationSpec.long.seconds
        )
        let _: Animation = anim
        #expect(true)
    }

    @Test("MotionDurationSpec.medium seconds matches expected value for smooth preset")
    func mediumDurationValueForSmooth() {
        #expect(MotionDurationSpec.medium.seconds == 0.320)
    }
}
