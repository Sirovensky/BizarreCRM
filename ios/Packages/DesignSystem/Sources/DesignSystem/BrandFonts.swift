import SwiftUI
import Core
#if canImport(UIKit)
import UIKit
import CoreText
#endif

// MARK: - BrandFonts
//
// §80.8 / §30.4 canonical scale — matches bizarreelectronics.com brand fonts:
//   Display / Titles  → Bebas Neue (condensed, all-caps)
//   Accent headings   → League Spartan (geometric sans)
//   Body / UI         → Roboto (workhorse)
//   Mono (IDs/codes)  → Roboto Mono
//
// Old families (Inter, Barlow Condensed, JetBrains Mono) are no longer used.
// Fallback when fonts are not registered: SF Pro / SF Mono of matching size.

public enum BrandFonts {
    private nonisolated(unsafe) static var didRegister = false

    public static func registerIfNeeded() {
        guard !didRegister else { return }
        didRegister = true
        // Fonts are registered via Info.plist `UIAppFonts`; this hook exists
        // for CI environments or SPM previews where runtime registration helps.
        AppLog.ui.debug("BrandFonts ready (§80.8 scale)")
    }
}

public extension Font {

    // MARK: - Display / Title — Bebas Neue (§80.8 largeTitle / title1)

    /// 34 pt  Bebas Neue — large screen titles, hero numbers.
    static func brandDisplayLarge()  -> Font {
        .custom("BebasNeue-Regular", size: 34, relativeTo: .largeTitle)
    }

    /// 28 pt  Bebas Neue — section / modal titles.
    static func brandDisplayMedium() -> Font {
        .custom("BebasNeue-Regular", size: 28, relativeTo: .title)
    }

    // MARK: - Accent / Secondary headings — League Spartan (§80.8 title2 / title3)

    /// 22 pt  League Spartan SemiBold — card headings, section subtitles.
    static func brandHeadlineLarge() -> Font {
        .custom("LeagueSpartan-SemiBold", size: 22, relativeTo: .title2)
    }

    /// 20 pt  League Spartan Medium — sub-section headings.
    static func brandHeadlineMedium() -> Font {
        .custom("LeagueSpartan-Medium", size: 20, relativeTo: .title3)
    }

    // MARK: - Body / UI — Roboto (§80.8 headline / body / callout / subheadline)

    /// 17 pt  Roboto SemiBold — emphasized labels, table header cells.
    static func brandTitleLarge() -> Font {
        .custom("Roboto-SemiBold", size: 17, relativeTo: .headline)
    }

    /// 16 pt  Roboto Medium — card titles, action labels.
    static func brandTitleMedium() -> Font {
        .custom("Roboto-Medium", size: 16, relativeTo: .callout)
    }

    /// 14 pt  Roboto Medium — row titles, chip labels.
    static func brandTitleSmall() -> Font {
        .custom("Roboto-Medium", size: 14, relativeTo: .subheadline)
    }

    /// 17 pt  Roboto Regular — paragraph body text.
    static func brandBodyLarge() -> Font {
        .custom("Roboto-Regular", size: 17, relativeTo: .body)
    }

    /// 14 pt  Roboto Regular — secondary body, form hints.
    static func brandBodyMedium() -> Font {
        .custom("Roboto-Regular", size: 14, relativeTo: .callout)
    }

    /// 14 pt  Roboto Medium — metadata labels, footnotes with emphasis.
    static func brandLabelLarge() -> Font {
        .custom("Roboto-Medium", size: 14, relativeTo: .footnote)
    }

    /// 12 pt  Roboto Regular — captions, table column headers.
    static func brandLabelSmall() -> Font {
        .custom("Roboto-Regular", size: 12, relativeTo: .caption)
    }

    // MARK: - KPI / Metric values (§91.10 — unified weight token)
    //
    // All KPI numeric values on report cards use this single token so weight
    // is consistent across RevenueChartCard, AvgTicketValueCard,
    // ExpensesChartCard, and FinancialDashboardView.
    //
    // 20 pt  League Spartan SemiBold — prominent enough to scan at a glance,
    // monospacedDigit applied at call site to prevent digit jitter.

    /// 20 pt  League Spartan SemiBold — unified KPI / metric value token.
    static func brandKpiValue() -> Font {
        .custom("LeagueSpartan-SemiBold", size: 20, relativeTo: .title3)
    }

    // MARK: - Mono — Roboto Mono (§80.8 mono)

    /// Roboto Mono Regular — IDs, SKUs, IMEI, barcodes, order numbers.
    static func brandMono(size: CGFloat = 14) -> Font {
        .custom("RobotoMono-Regular", size: size, relativeTo: .body)
    }

    // MARK: - Chart axis labels (§91.10 — explicit size token)
    //
    // Swift Charts applies system default sizing to axis labels; override to
    // a consistent 11 pt Roboto Regular so axis context stays legible without
    // competing with data marks.

    /// 11 pt  Roboto Regular — chart x/y axis labels and annotations.
    static func brandChartAxisLabel() -> Font {
        .custom("Roboto-Regular", size: 11, relativeTo: .caption2)
    }
}
