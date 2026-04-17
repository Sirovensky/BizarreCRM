import SwiftUI
import Core
#if canImport(UIKit)
import UIKit
import CoreText
#endif

public enum BrandFonts {
    private nonisolated(unsafe) static var didRegister = false

    public static func registerIfNeeded() {
        guard !didRegister else { return }
        didRegister = true
        // Fonts are registered via Info.plist `UIAppFonts`; this hook exists
        // for CI environments or SPM previews where runtime registration helps.
        AppLog.ui.debug("BrandFonts ready")
    }
}

public extension Font {
    static func brandDisplayLarge()  -> Font { .custom("BarlowCondensed-SemiBold", size: 57, relativeTo: .largeTitle) }
    static func brandDisplayMedium() -> Font { .custom("BarlowCondensed-SemiBold", size: 45, relativeTo: .largeTitle) }
    static func brandHeadlineLarge() -> Font { .custom("BarlowCondensed-SemiBold", size: 32, relativeTo: .title) }
    static func brandHeadlineMedium()-> Font { .custom("BarlowCondensed-SemiBold", size: 28, relativeTo: .title2) }
    static func brandTitleLarge()    -> Font { .custom("Inter-SemiBold", size: 22, relativeTo: .title3) }
    static func brandTitleMedium()   -> Font { .custom("Inter-SemiBold", size: 16, relativeTo: .headline) }
    static func brandTitleSmall()    -> Font { .custom("Inter-SemiBold", size: 14, relativeTo: .subheadline) }
    static func brandBodyLarge()     -> Font { .custom("Inter-Regular",  size: 16, relativeTo: .body) }
    static func brandBodyMedium()    -> Font { .custom("Inter-Regular",  size: 14, relativeTo: .callout) }
    static func brandLabelLarge()    -> Font { .custom("Inter-Medium",   size: 14, relativeTo: .footnote) }
    static func brandLabelSmall()    -> Font { .custom("Inter-Medium",   size: 12, relativeTo: .caption) }
    static func brandMono(size: CGFloat = 14) -> Font {
        .custom("JetBrainsMono-Regular", size: size, relativeTo: .body)
    }
}
