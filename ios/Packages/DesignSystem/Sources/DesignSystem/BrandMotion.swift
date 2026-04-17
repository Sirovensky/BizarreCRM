import SwiftUI

public enum BrandMotion {
    public static let fab:            Animation = .spring(response: 0.35, dampingFraction: 0.78)
    public static let offlineBanner:  Animation = .easeInOut(duration: 0.20)
    public static let syncPulse:      Animation = .easeInOut(duration: 0.60).repeatForever(autoreverses: true)
    public static let sheet:          Animation = .spring(response: 0.45, dampingFraction: 0.88)
    public static let listInsert:     Animation = .smooth(duration: 0.24)
    public static let statusChange:   Animation = .bouncy(duration: 0.45, extraBounce: 0.15)
    public static let barcodeSuccess: Animation = .snappy(duration: 0.18)
}
