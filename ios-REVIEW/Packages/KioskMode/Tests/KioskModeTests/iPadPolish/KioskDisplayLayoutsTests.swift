import Testing
import Foundation
@testable import KioskMode

// MARK: - KioskDisplayLayouts tests

@Suite("KioskDisplayLayouts §22")
@MainActor
struct KioskDisplayLayoutsTests {

    // MARK: - KioskDisplayVariant metrics

    @Test("Landscape metrics use expected horizontal padding")
    func landscapeHorizontalPadding() {
        let m = KioskDisplayVariant.landscape.metrics
        #expect(m.horizontalPadding == 48)
    }

    @Test("Landscape metrics show no sidebar")
    func landscapeNoSidebar() {
        let m = KioskDisplayVariant.landscape.metrics
        #expect(!m.showsSidebar)
        #expect(m.sidebarWidth == 0)
    }

    @Test("Portrait metrics use smaller horizontal padding than landscape")
    func portraitSmallerHorizontal() {
        let landscape = KioskDisplayVariant.landscape.metrics
        let portrait  = KioskDisplayVariant.portrait.metrics
        // Portrait is narrower — vertical padding is larger, horizontal is smaller
        #expect(portrait.horizontalPadding < landscape.horizontalPadding)
    }

    @Test("Portrait metrics show no sidebar")
    func portraitNoSidebar() {
        let m = KioskDisplayVariant.portrait.metrics
        #expect(!m.showsSidebar)
        #expect(m.sidebarWidth == 0)
    }

    @Test("DualScreen metrics show sidebar with positive width")
    func dualScreenHasSidebar() {
        let m = KioskDisplayVariant.dualScreen.metrics
        #expect(m.showsSidebar)
        #expect(m.sidebarWidth > 0)
    }

    @Test("DualScreen sidebar width is at least 200pt")
    func dualScreenSidebarMinWidth() {
        let m = KioskDisplayVariant.dualScreen.metrics
        #expect(m.sidebarWidth >= 200)
    }

    @Test("All variants have positive section spacing")
    func allVariantsSectionSpacingPositive() {
        for variant in [KioskDisplayVariant.landscape, .portrait, .dualScreen] {
            #expect(variant.metrics.sectionSpacing > 0)
        }
    }

    @Test("All variants have positive heroCenterMaxWidth")
    func allVariantsHeroMaxWidth() {
        for variant in [KioskDisplayVariant.landscape, .portrait, .dualScreen] {
            #expect(variant.metrics.heroCenterMaxWidth > 0)
        }
    }

    @Test("All variants have positive contentColumnWidth")
    func allVariantsContentColumnWidth() {
        for variant in [KioskDisplayVariant.landscape, .portrait, .dualScreen] {
            #expect(variant.metrics.contentColumnWidth > 0)
        }
    }

    @Test("Variant equality: same variant equals itself")
    func variantEquality() {
        #expect(KioskDisplayVariant.landscape == .landscape)
        #expect(KioskDisplayVariant.portrait  == .portrait)
        #expect(KioskDisplayVariant.dualScreen == .dualScreen)
    }

    @Test("Variant inequality: different variants are not equal")
    func variantInequality() {
        #expect(KioskDisplayVariant.landscape != .portrait)
        #expect(KioskDisplayVariant.portrait  != .dualScreen)
        #expect(KioskDisplayVariant.landscape != .dualScreen)
    }

    // MARK: - KioskLayoutMetrics equality

    @Test("KioskLayoutMetrics equality: same values are equal")
    func metricsEquality() {
        let a = KioskLayoutMetrics(
            horizontalPadding: 48, verticalPadding: 32,
            sidebarWidth: 0, contentColumnWidth: 600,
            sectionSpacing: 32, showsSidebar: false,
            heroCenterMaxWidth: 560
        )
        let b = KioskLayoutMetrics(
            horizontalPadding: 48, verticalPadding: 32,
            sidebarWidth: 0, contentColumnWidth: 600,
            sectionSpacing: 32, showsSidebar: false,
            heroCenterMaxWidth: 560
        )
        #expect(a == b)
    }

    @Test("KioskLayoutMetrics inequality: differing padding")
    func metricsInequality() {
        let a = KioskLayoutMetrics(
            horizontalPadding: 48, verticalPadding: 32,
            sidebarWidth: 0, contentColumnWidth: 600,
            sectionSpacing: 32, showsSidebar: false,
            heroCenterMaxWidth: 560
        )
        let b = KioskLayoutMetrics(
            horizontalPadding: 16, verticalPadding: 32,
            sidebarWidth: 0, contentColumnWidth: 600,
            sectionSpacing: 32, showsSidebar: false,
            heroCenterMaxWidth: 560
        )
        #expect(a != b)
    }

    // MARK: - Landscape vs dualScreen

    @Test("DualScreen section spacing equals portrait section spacing")
    func dualScreenMatchesPortraitSectionSpacing() {
        #expect(
            KioskDisplayVariant.dualScreen.metrics.sectionSpacing
            == KioskDisplayVariant.portrait.metrics.sectionSpacing
        )
    }

    @Test("Landscape heroCenterMaxWidth is wider than portrait")
    func landscapeHeroWiderThanPortrait() {
        #expect(
            KioskDisplayVariant.landscape.metrics.heroCenterMaxWidth
            > KioskDisplayVariant.portrait.metrics.heroCenterMaxWidth
        )
    }
}
