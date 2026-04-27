import SwiftUI
import WidgetKit
#if canImport(UIKit)
import UIKit
#endif

// MARK: - §24.6 Control Center controls (iOS 18+)
//
// Each `ControlWidget` appears in Settings → Control Center.
// Users add them to the Control Center customization.
// Controls use App Intents (already in Intents/) for actions.
//
// NOTE: ControlWidget requires iOS 18 — gated at the call site.

#if swift(>=5.10)
import ControlCenter

// MARK: - Clock In/Out Toggle Control

/// §24.6 — One-tap clock in/out toggle in Control Center.
@available(iOS 18.0, *)
struct ClockInOutControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: "com.bizarrecrm.control.clockinout"
        ) {
            ControlWidgetToggle(
                "Clock In/Out",
                isOn: ClockStateProvider.isClockIn,
                action: ClockInOutControlIntent()
            ) { isOn in
                Label(
                    isOn ? "Clocked In" : "Clocked Out",
                    systemImage: isOn ? "clock.fill" : "clock"
                )
            }
        }
        .displayName("Clock In/Out")
        .description("Toggle your shift clock directly from Control Center.")
    }
}

// MARK: - Quick Scan Control

/// §24.6 — Opens scanner from Control Center.
@available(iOS 18.0, *)
struct QuickScanControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: "com.bizarrecrm.control.quickscan"
        ) {
            ControlWidgetButton(
                action: OpenScannerControlIntent()
            ) {
                Label("Scan", systemImage: "barcode.viewfinder")
            }
        }
        .displayName("Quick Scan")
        .description("Open the barcode scanner from Control Center.")
    }
}

// MARK: - Quick Sale Control

/// §24.6 — Opens POS from Control Center.
@available(iOS 18.0, *)
struct QuickSaleControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: "com.bizarrecrm.control.quicksale"
        ) {
            ControlWidgetButton(
                action: OpenPosControlIntent()
            ) {
                Label("New Sale", systemImage: "cart.badge.plus")
            }
        }
        .displayName("Quick Sale")
        .description("Open the POS from Control Center.")
    }
}

// MARK: - SMS Unread Badge Control

/// §24.6 — Shows unread SMS count in Control Center; taps to open SMS tab.
@available(iOS 18.0, *)
struct SMSUnreadControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: "com.bizarrecrm.control.smsunread"
        ) {
            ControlWidgetButton(
                action: OpenSMSControlIntent()
            ) {
                Label {
                    Text("SMS")
                } icon: {
                    // Badge value fed from App Group UserDefaults
                    let count = SMSBadgeProvider.unreadCount
                    Image(systemName: count > 0 ? "message.badge.filled.fill" : "message")
                }
            }
        }
        .displayName("SMS Unread")
        .description("See unread SMS count and jump to the inbox.")
    }
}

// MARK: - Data providers (App Group UserDefaults)

/// Reads clock-in state from App Group shared UserDefaults.
/// Updated by main app on clock-in/out events.
private enum ClockStateProvider {
    static var isClockIn: Bool {
        UserDefaults(suiteName: "group.com.bizarrecrm")?
            .bool(forKey: "control.isClockIn") ?? false
    }
}

/// Reads SMS unread count from App Group shared UserDefaults.
private enum SMSBadgeProvider {
    static var unreadCount: Int {
        UserDefaults(suiteName: "group.com.bizarrecrm")?
            .integer(forKey: "control.smsUnreadCount") ?? 0
    }
}

// MARK: - Control Intents (thin wrappers — open app via URL scheme)

import AppIntents

@available(iOS 18.0, *)
struct ClockInOutControlIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Clock In/Out"
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        // Navigate to timeclock tab; the Timeclock ViewModel handles the toggle.
        await openURL("bizarrecrm://timeclock")
        return .result()
    }
}

@available(iOS 16.0, *)
struct OpenScannerControlIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Scanner"
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        await openURL("bizarrecrm://scanner")
        return .result()
    }
}

@available(iOS 16.0, *)
struct OpenPosControlIntent: AppIntent {
    static var title: LocalizedStringResource = "Open POS"
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        await openURL("bizarrecrm://pos")
        return .result()
    }
}

@available(iOS 16.0, *)
struct OpenSMSControlIntent: AppIntent {
    static var title: LocalizedStringResource = "Open SMS Inbox"
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        await openURL("bizarrecrm://sms")
        return .result()
    }
}

// MARK: - URL helper

@MainActor
private func openURL(_ urlString: String) async {
    #if canImport(UIKit)
    guard let url = URL(string: urlString) else { return }
    await UIApplication.shared.open(url)
    #endif
}

#endif // swift(>=5.10)
