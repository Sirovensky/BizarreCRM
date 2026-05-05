import Testing
import SwiftUI
@testable import DesignSystem

// §30 — ReduceTransparencyFallback tests

@Suite("ReduceTransparencyFallback")
struct ReduceTransparencyFallbackTests {

    @Test("Modifier struct initialises with a color and capsule shape")
    func initWithCapsule() {
        let mod = ReduceTransparencyFallbackModifier(
            replacementColor: Color.white,
            in: Capsule()
        )
        let _: ReduceTransparencyFallbackModifier<Capsule> = mod
        #expect(true)
    }

    @Test("Modifier struct initialises with a RoundedRectangle shape")
    func initWithRoundedRect() {
        let mod = ReduceTransparencyFallbackModifier(
            replacementColor: .white,
            in: RoundedRectangle(cornerRadius: 12)
        )
        let _: ReduceTransparencyFallbackModifier<RoundedRectangle> = mod
        #expect(true)
    }

    @Test("View.reduceTransparencyFallback(in:) compiles with RoundedRectangle")
    @MainActor func viewExtensionWithShape() {
        let view = Text("hello")
            .reduceTransparencyFallback(.white, in: RoundedRectangle(cornerRadius: 8))
        _ = view
        #expect(true)
    }

    @Test("View.reduceTransparencyFallback() capsule overload compiles")
    @MainActor func viewExtensionCapsule() {
        let view = Text("badge")
            .reduceTransparencyFallback(.gray)
        _ = view
        #expect(true)
    }

    @Test("View.reduceTransparencyFallback() default color compiles")
    @MainActor func viewExtensionDefaultColor() {
        let view = Text("badge")
            .reduceTransparencyFallback()
        _ = view
        #expect(true)
    }
}
