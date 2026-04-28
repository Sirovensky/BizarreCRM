import SwiftUI
import Core
#if canImport(UIKit)
import UIKit
import CoreText
#endif

// MARK: - BrandFonts

/// §30.4 Brand font families.
///
/// Canonical family (per ActionPlan §30.4 / §80.8, aligned with bizarreelectronics.com):
///   - **Bebas Neue Regular** — display/title (large numbers, screen headers, CTAs)
///   - **League Spartan SemiBold/Bold** — accent/secondary headings
///   - **Roboto** — body/UI workhorse (replaces Inter)
///   - **Roboto Mono** — monospace (IDs, SKUs, IMEIs, barcodes, log output)
///   - **Roboto Slab SemiBold** — optional slab accent (invoice print header)
///
/// All weights fall back to SF Pro / SF Mono if the font file is missing
/// (i.e. `fetch-fonts.sh` has not been run). **Never crash** — the fallback
/// is logged once to the dev console per session.
public enum BrandFonts {
    private nonisolated(unsafe) static var didRegister = false
    private nonisolated(unsafe) static var didWarnMissing = false

    /// Call at app launch (or in SwiftUI previews). Fonts are already registered
    /// via `Info.plist UIAppFonts`; this hook logs a one-time dev-console warning
    /// when the font files are absent (fetch-fonts.sh not run yet).
    public static func registerIfNeeded() {
        guard !didRegister else { return }
        didRegister = true

        #if canImport(UIKit)
        // Probe for one of our brand fonts. If missing, log once and continue —
        // SF Pro fallback kicks in transparently.
        let probe = UIFont(name: "BebasNeue-Regular", size: 17)
        if probe == nil, !didWarnMissing {
            didWarnMissing = true
            AppLog.ui.warning("""
                BrandFonts: brand font files not found. \
                Run 'bash ios/scripts/fetch-fonts.sh' then regenerate the project. \
                Falling back to SF Pro.
                """)
        }
        #endif
    }
}

// MARK: - Font scale (§80.8)

public extension Font {
    // MARK: Display — Bebas Neue Regular (condensed all-caps)

    /// `largeTitle` — 34pt Bebas Neue Regular. Dashboards, large revenue numbers.
    static func brandLargeTitle() -> Font {
        .custom("BebasNeue-Regular", size: 34, relativeTo: .largeTitle)
    }

    /// `title1` — 28pt Bebas Neue Regular. Screen headers.
    static func brandTitle1() -> Font {
        .custom("BebasNeue-Regular", size: 28, relativeTo: .title)
    }

    // MARK: Accent — League Spartan SemiBold / Medium

    /// `title2` — 22pt League Spartan SemiBold. Section subtitles, empty-state heads.
    static func brandTitle2() -> Font {
        .custom("LeagueSpartan-SemiBold", size: 22, relativeTo: .title2)
    }

    /// `title3` — 20pt League Spartan Medium. Minor section headings.
    static func brandTitle3() -> Font {
        .custom("LeagueSpartan-Medium", size: 20, relativeTo: .title3)
    }

    // MARK: Body — Roboto (workhorse)

    /// `headline` — 17pt Roboto SemiBold. List-row primary label.
    static func brandHeadline() -> Font {
        .custom("Roboto-SemiBold", size: 17, relativeTo: .headline)
    }

    /// `body` — 17pt Roboto Regular. General body text.
    static func brandBody() -> Font {
        .custom("Roboto-Regular", size: 17, relativeTo: .body)
    }

    /// `callout` — 16pt Roboto Regular. Callout copy, badges.
    static func brandCallout() -> Font {
        .custom("Roboto-Regular", size: 16, relativeTo: .callout)
    }

    /// `subheadline` — 15pt Roboto Regular. Secondary labels.
    static func brandSubheadline() -> Font {
        .custom("Roboto-Regular", size: 15, relativeTo: .subheadline)
    }

    /// `footnote` — 13pt Roboto Regular. Timestamps, helper text.
    static func brandFootnote() -> Font {
        .custom("Roboto-Regular", size: 13, relativeTo: .footnote)
    }

    /// `caption1` — 12pt Roboto Regular. Table cell secondary.
    static func brandCaption1() -> Font {
        .custom("Roboto-Regular", size: 12, relativeTo: .caption)
    }

    /// `caption2` — 11pt Roboto Regular. Timestamps in dense rows.
    static func brandCaption2() -> Font {
        .custom("Roboto-Regular", size: 11, relativeTo: .caption2)
    }

    // MARK: Monospace — Roboto Mono

    /// `mono` — 14pt Roboto Mono Regular. IDs, SKUs, IMEI, barcodes, order numbers.
    /// Use `.monospacedDigit()` variant for counters / totals so digits don't jitter.
    static func brandMono(size: CGFloat = 14) -> Font {
        .custom("RobotoMono-Regular", size: size, relativeTo: .body)
    }

    // MARK: Slab accent — Roboto Slab (optional, invoice print header)

    /// Roboto Slab SemiBold. Use sparingly — invoice-total print headers, one accent spot.
    static func brandSlab(size: CGFloat = 16) -> Font {
        .custom("RobotoSlab-SemiBold", size: size, relativeTo: .body)
    }

    // MARK: - Legacy aliases (kept for migration; prefer named helpers above)

    /// @deprecated Use `brandTitle1()` or `brandTitle2()`.
    static func brandDisplayLarge() -> Font { brandLargeTitle() }
    /// @deprecated Use `brandTitle2()`.
    static func brandDisplayMedium() -> Font { brandTitle2() }
    /// @deprecated Use `brandTitle1()`.
    static func brandHeadlineLarge() -> Font { brandTitle1() }
    /// @deprecated Use `brandTitle2()`.
    static func brandHeadlineMedium() -> Font { brandTitle2() }
    /// @deprecated Use `brandTitle2()`.
    static func brandTitleLarge() -> Font { brandTitle2() }
    /// @deprecated Use `brandHeadline()`.
    static func brandTitleMedium() -> Font { brandHeadline() }
    /// @deprecated Use `brandSubheadline()`.
    static func brandTitleSmall() -> Font { brandSubheadline() }
    /// @deprecated Use `brandBody()`.
    static func brandBodyLarge() -> Font { brandBody() }
    /// @deprecated Use `brandCallout()`.
    static func brandBodyMedium() -> Font { brandCallout() }
    /// @deprecated Use `brandFootnote()`.
    static func brandLabelLarge() -> Font { brandFootnote() }
    /// @deprecated Use `brandCaption1()`.
    static func brandLabelSmall() -> Font { brandCaption1() }
    /// @deprecated Use `brandTitle3()` / `brandHeadline()`.
    static func brandDisplaySmall() -> Font { brandTitle3() }
    /// @deprecated Use `brandCaption1()`.
    static func brandCaption() -> Font { brandCaption1() }
    /// @deprecated Use `brandBody()` / `brandCallout()`.
    static func brandLabelMedium() -> Font { brandFootnote() }
    /// @deprecated Use `brandFootnote()`.
    static func brandBodySmall() -> Font { brandFootnote() }
}
