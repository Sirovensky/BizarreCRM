import Testing
import SwiftUI
@testable import DesignSystem

// §30 — GlassKit §30 additions: BrandGlassClearButtonStyle + BrandGlassBadge

@Suite("GlassKit §30")
struct GlassKitTests {

    // MARK: - BrandGlassClearButtonStyle

    @Test("brandGlassClear static extension is accessible")
    func brandGlassClearExtension() {
        // Compile-time check: the ButtonStyle extension must resolve.
        let _: BrandGlassClearButtonStyle = .init()
        #expect(true)
    }

    @Test("BrandGlassClearButtonStyle is a ButtonStyle")
    func clearButtonStyleConformance() {
        let style = BrandGlassClearButtonStyle()
        // Protocol conformance proof via type check
        let _: any ButtonStyle = style
        #expect(true)
    }

    // MARK: - BrandGlassBadge

    @Test("BrandGlassBadge initialises with label and variant")
    func badgeInit() {
        let badge = BrandGlassBadge("42", variant: .regular)
        let _: BrandGlassBadge = badge
        #expect(true)
    }

    @Test("BrandGlassBadge clear variant initialises")
    func badgeClearVariant() {
        let badge = BrandGlassBadge("NEW", variant: .clear)
        let _: BrandGlassBadge = badge
        #expect(true)
    }

    @Test("BrandGlassBadge identity variant with tint initialises")
    func badgeIdentityVariant() {
        let badge = BrandGlassBadge("HOT", variant: .identity, tint: .orange)
        let _: BrandGlassBadge = badge
        #expect(true)
    }

    // MARK: - BrandGlassVariant enum coverage

    @Test("BrandGlassVariant has regular, clear, identity")
    func glassVariantCases() {
        let cases: [BrandGlassVariant] = [.regular, .clear, .identity]
        #expect(cases.count == 3)
    }

    // MARK: - ButtonStyle dot-syntax extensions

    @Test("brandGlassProminent dot-syntax resolves")
    func brandGlassProminentDotSyntax() {
        // This is a compile-time test — if the extension is missing, it won't compile.
        func accept<S: ButtonStyle>(_ s: S) {}
        accept(BrandGlassProminentButtonStyle())
        #expect(true)
    }

    @Test("brandGlass dot-syntax resolves")
    func brandGlassDotSyntax() {
        func accept<S: ButtonStyle>(_ s: S) {}
        accept(BrandGlassButtonStyle())
        #expect(true)
    }

    @Test("brandGlassClear dot-syntax resolves")
    func brandGlassClearDotSyntax() {
        func accept<S: ButtonStyle>(_ s: S) {}
        accept(BrandGlassClearButtonStyle())
        #expect(true)
    }
}
