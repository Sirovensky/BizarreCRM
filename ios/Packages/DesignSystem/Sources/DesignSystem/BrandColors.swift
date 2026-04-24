import SwiftUI

public extension Color {
    static let bizarreSurfaceBase        = Color("SurfaceBase",           bundle: .main)
    static let bizarreSurface1           = Color("Surface1",              bundle: .main)
    static let bizarreSurface2           = Color("Surface2",              bundle: .main)
    static let bizarreOutline            = Color("Outline",               bundle: .main)
    static let bizarreOnSurface          = Color("OnSurface",             bundle: .main)
    static let bizarreOnSurfaceMuted     = Color("OnSurfaceMuted",        bundle: .main)
    static let bizarreOrange             = Color("BrandOrange",           bundle: .main)
    static let bizarreOrangeContainer    = Color("BrandOrangeContainer",  bundle: .main)
    static let bizarreOnOrange           = Color("OnBrandOrange",         bundle: .main)
    static let bizarreTeal               = Color("BrandTeal",             bundle: .main)
    static let bizarreMagenta            = Color("BrandMagenta",          bundle: .main)
    static let bizarreSuccess            = Color("SuccessGreen",          bundle: .main)
    static let bizarreWarning            = Color("WarningAmber",          bundle: .main)
    static let bizarreError              = Color("ErrorRose",             bundle: .main)
    // §30 — Semantic badge additions
    static let bizarreDanger             = Color("DangerRed",             bundle: .main)
    static let bizarreInfo               = Color("InfoBlue",              bundle: .main)
}

// Mirror the brand colors onto ShapeStyle so dot-syntax works at call
// sites like `.foregroundStyle(.bizarreOrange)` and `.fill(.bizarreTeal)`.
public extension ShapeStyle where Self == Color {
    static var bizarreSurfaceBase:     Color { .bizarreSurfaceBase }
    static var bizarreSurface1:        Color { .bizarreSurface1 }
    static var bizarreSurface2:        Color { .bizarreSurface2 }
    static var bizarreOutline:         Color { .bizarreOutline }
    static var bizarreOnSurface:       Color { .bizarreOnSurface }
    static var bizarreOnSurfaceMuted:  Color { .bizarreOnSurfaceMuted }
    static var bizarreOrange:          Color { .bizarreOrange }
    static var bizarreOrangeContainer: Color { .bizarreOrangeContainer }
    static var bizarreOnOrange:        Color { .bizarreOnOrange }
    static var bizarreTeal:            Color { .bizarreTeal }
    static var bizarreMagenta:         Color { .bizarreMagenta }
    static var bizarreSuccess:         Color { .bizarreSuccess }
    static var bizarreWarning:         Color { .bizarreWarning }
    static var bizarreError:           Color { .bizarreError }
    // §30 — Semantic badge additions
    static var bizarreDanger:          Color { .bizarreDanger }
    static var bizarreInfo:            Color { .bizarreInfo }
}
