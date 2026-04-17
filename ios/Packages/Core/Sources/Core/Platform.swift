import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(SwiftUI)
import SwiftUI
#endif

public enum Platform {
    public static var isMac: Bool {
        #if targetEnvironment(macCatalyst)
        return true
        #else
        return ProcessInfo.processInfo.isiOSAppOnMac
        #endif
    }

    public static var isIPad: Bool {
        #if canImport(UIKit)
        UIDevice.current.userInterfaceIdiom == .pad && !isMac
        #else
        false
        #endif
    }

    public static var isIPhone: Bool {
        #if canImport(UIKit)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    public static var isCompact: Bool { isIPhone }

    public static var supportsNativeBarcodeScan: Bool { !isMac }
    public static var supportsBluetoothClassicPrinter: Bool { !isMac }
    public static var supportsHaptics: Bool { isIPhone }

    public static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    public static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }
}
