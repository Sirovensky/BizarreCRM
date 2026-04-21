import WidgetKit
import SwiftUI

/// Widget bundle entry point — lists every widget provided by this extension.
///
/// The widget extension `Info.plist` must contain:
/// ```xml
/// <key>NSExtension</key>
/// <dict>
///   <key>NSExtensionPointIdentifier</key>
///   <string>com.apple.widgetkit-extension</string>
/// </dict>
/// ```
@main
struct BizarreCRMWidgetBundle: WidgetBundle {
    var body: some Widget {
        // Home Screen + StandBy
        OpenTicketsWidget()
        TodaysRevenueWidget()
        AppointmentsNextWidget()
        // Lock Screen complications
        LockScreenComplicationsWidget()
        // Live Activities
        ClockInOutLiveActivity()
        SaleInProgressLiveActivity()
    }
}
