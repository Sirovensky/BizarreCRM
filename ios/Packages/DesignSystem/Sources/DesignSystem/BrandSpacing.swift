import CoreGraphics

public enum BrandSpacing {
    public static let xxs:  CGFloat = 2
    public static let xs:   CGFloat = 4
    public static let sm:   CGFloat = 8
    public static let md:   CGFloat = 12
    public static let base: CGFloat = 16
    public static let lg:   CGFloat = 24
    public static let xl:   CGFloat = 32
    public static let xxl:  CGFloat = 48
    public static let xxxl: CGFloat = 64
}

public extension CGFloat {
    static let bsXxs  = BrandSpacing.xxs
    static let bsXs   = BrandSpacing.xs
    static let bsSm   = BrandSpacing.sm
    static let bsMd   = BrandSpacing.md
    static let bsBase = BrandSpacing.base
    static let bsLg   = BrandSpacing.lg
    static let bsXl   = BrandSpacing.xl
    static let bsXxl  = BrandSpacing.xxl
}
