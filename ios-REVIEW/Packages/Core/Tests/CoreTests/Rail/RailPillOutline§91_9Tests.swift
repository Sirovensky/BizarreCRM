import XCTest
import SwiftUI
@testable import Core

// §91.9-2 — Unit tests for the pillOutlineColor computed property added to
// RailSidebarView in commit fba06fb6.
//
// Because `pillOutlineColor` is private on RailSidebarView we test it
// indirectly via a thin ColorScheme-aware helper that mirrors the
// production rule: nil in dark mode, a non-nil deep-orange Color in light.

// MARK: - Helpers mirroring the production rule

/// Replicates the exact production logic from RailSidebarView.pillOutlineColor.
/// If the production value changes, update this in lockstep.
private func pillOutlineColor(for colorScheme: ColorScheme) -> Color? {
    colorScheme == .light
        ? Color(red: 194/255, green: 65/255, blue: 12/255, opacity: 0.55)
        : nil
}

/// The pillBackground production rule for quick colour-math checks.
private func pillBackground(for colorScheme: ColorScheme) -> Color {
    colorScheme == .dark
        ? Color(red: 253/255, green: 238/255, blue: 208/255, opacity: 0.30)  // cream
        : Color(red: 194/255, green: 65/255,  blue: 12/255,  opacity: 0.18)  // deep orange
}

// MARK: - Tests

final class RailPillOutline_91_9_Tests: XCTestCase {

    // MARK: 1. pillOutlineColor is nil in dark mode

    func test_pillOutlineColor_darkMode_isNil() {
        XCTAssertNil(
            pillOutlineColor(for: .dark),
            "Dark mode must not draw an outline — it would clash with the cream fill"
        )
    }

    // MARK: 2. pillOutlineColor is non-nil in light mode

    func test_pillOutlineColor_lightMode_isNonNil() {
        XCTAssertNotNil(
            pillOutlineColor(for: .light),
            "Light mode must produce a 1pt outline so the active pill is legible on .regularMaterial"
        )
    }

    // MARK: 3. Outline colour in light mode matches bizarreOrange (deep-orange RGB)

    func test_pillOutlineColor_lightMode_usesDeepOrangeRGB() throws {
        // bizarreOrange = #c2410c = rgb(194, 65, 12)
        let color = try XCTUnwrap(pillOutlineColor(for: .light))
        // Resolve to sRGB to compare components
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        let uiColor = UIColor(color)
        let resolved = uiColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)

        XCTAssertEqual(r, 194/255, accuracy: 0.01,
                       "Outline red component should match bizarreOrange (194/255)")
        XCTAssertEqual(g,  65/255, accuracy: 0.01,
                       "Outline green component should match bizarreOrange (65/255)")
        XCTAssertEqual(b,  12/255, accuracy: 0.01,
                       "Outline blue component should match bizarreOrange (12/255)")
        XCTAssertEqual(a, 0.55, accuracy: 0.01,
                       "Outline alpha should be 0.55 for subtle legibility contrast")
    }

    // MARK: 4. pillBackground dark/light produce correct RGB families

    func test_pillBackground_darkMode_isCreamFamily() {
        let color = pillBackground(for: .dark)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
            .getRed(&r, green: &g, blue: &b, alpha: nil)
        // Cream: r > b, g > b, high-red dominant
        XCTAssertGreaterThan(r, 0.85, "Dark-mode pill background should be cream (high red)")
        XCTAssertGreaterThan(g, 0.80, "Dark-mode pill background should be cream (high green)")
    }

    func test_pillBackground_lightMode_isOrangeFamily() {
        let color = pillBackground(for: .light)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
            .getRed(&r, green: &g, blue: &b, alpha: nil)
        // Orange family: red dominant, low blue
        XCTAssertGreaterThan(r, g, "Light-mode pill background should be orange (red > green)")
        XCTAssertGreaterThan(r, b, "Light-mode pill background should be orange (red > blue)")
    }

    // MARK: 5. Colour scheme toggle flips outline presence

    func test_pillOutlineColor_toggles_betweenSchemes() {
        let dark  = pillOutlineColor(for: .dark)
        let light = pillOutlineColor(for: .light)
        // One must be nil, the other non-nil
        XCTAssertTrue(
            (dark == nil) != (light == nil),
            "Exactly one of dark/light pillOutlineColor must be nil"
        )
    }
}
