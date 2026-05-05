// DesignSystem/Tips/TipCatalog.swift
//
// Pre-defined TipKit tips for BizarreCRM.
// All eligibility computation is on-device; no third-party egress.
//
// TipKit is iOS 17+ and not available on macOS via SwiftPM on linux runners.
// All declarations are guarded with #if canImport(TipKit).
//
// §26 Sticky a11y tips (Phase 10)

#if canImport(TipKit)
import TipKit

// MARK: - Codable event payload

/// Minimal Codable type used as the TipKit `Event` parameter.
/// `Event<Void>` is rejected by the compiler (Void is not Codable).
@available(iOS 17, *)
public struct TipEventPayload: Codable, Sendable {
    public init() {}
}

// MARK: - Tips

/// "Press ⌘K to open Command Palette"
/// Shown once, after 3 app launches.
@available(iOS 17, *)
public struct CommandPaletteTip: BrandTip {
    public static let appLaunched = Event<TipEventPayload>(id: "app_launched_for_command_palette")

    public var title: Text { Text("Open Command Palette") }
    public var message: Text? { Text("Press ⌘K anywhere to search, navigate, or act instantly.") }
    public var image: Image? { Image(systemName: "command") }

    public var rules: [Rule] {
        [
            #Rule(Self.appLaunched) { $0.donations.count >= 3 }
        ]
    }

    public var options: [any TipOption] {
        [Tips.MaxDisplayCount(1)]
    }

    public init() {}
}

/// "Swipe left on any ticket to archive"
/// Shown once, after the Tickets list has been seen.
@available(iOS 17, *)
public struct SwipeToArchiveTip: BrandTip {
    public static let ticketsListViewed = Event<TipEventPayload>(id: "tickets_list_viewed")

    public var title: Text { Text("Quick Archive") }
    public var message: Text? { Text("Swipe left on any ticket to archive it in one gesture.") }
    public var image: Image? { Image(systemName: "archivebox") }

    public var rules: [Rule] {
        [
            #Rule(Self.ticketsListViewed) { $0.donations.count >= 1 }
        ]
    }

    public var options: [any TipOption] {
        [Tips.MaxDisplayCount(1)]
    }

    public init() {}
}

/// "Pull down any list to refresh"
/// Shown on first launch.
@available(iOS 17, *)
public struct PullToRefreshTip: BrandTip {
    public static let appLaunched = Event<TipEventPayload>(id: "app_launched_for_pull_refresh")

    public var title: Text { Text("Pull to Refresh") }
    public var message: Text? { Text("Pull down any list to fetch the latest data from your server.") }
    public var image: Image? { Image(systemName: "arrow.down.circle") }

    public var rules: [Rule] {
        [
            #Rule(Self.appLaunched) { $0.donations.count >= 1 }
        ]
    }

    public var options: [any TipOption] {
        [Tips.MaxDisplayCount(1)]
    }

    public init() {}
}

/// "Long-press any row for quick actions"
@available(iOS 17, *)
public struct ContextMenuTip: BrandTip {
    public static let rowViewed = Event<TipEventPayload>(id: "list_row_viewed_for_context_menu")

    public var title: Text { Text("Quick Actions") }
    public var message: Text? { Text("Long-press any row to see shortcuts like Edit, Archive, or Share.") }
    public var image: Image? { Image(systemName: "hand.tap") }

    public var rules: [Rule] {
        [
            #Rule(Self.rowViewed) { $0.donations.count >= 1 }
        ]
    }

    public var options: [any TipOption] {
        [Tips.MaxDisplayCount(1)]
    }

    public init() {}
}

/// "Tap camera icon in SKU field to scan"
@available(iOS 17, *)
public struct ScanBarcodeTip: BrandTip {
    public static let skuFieldViewed = Event<TipEventPayload>(id: "sku_field_viewed")

    public var title: Text { Text("Scan Barcode") }
    public var message: Text? { Text("Tap the camera icon next to the SKU field to scan a barcode instantly.") }
    public var image: Image? { Image(systemName: "barcode.viewfinder") }

    public var rules: [Rule] {
        [
            #Rule(Self.skuFieldViewed) { $0.donations.count >= 1 }
        ]
    }

    public var options: [any TipOption] {
        [Tips.MaxDisplayCount(1)]
    }

    public init() {}
}

/// "Open POS to start your first sale — tap POS in the tab bar"
/// Shown once after the first app launch, guiding new users to the Point of Sale.
@available(iOS 17, *)
public struct PosQuickStartTip: BrandTip {
    public static let appLaunched = Event<TipEventPayload>(id: "app_launched_for_pos_quick_start")

    public var title: Text { Text("Start a Sale") }
    public var message: Text? { Text("Tap POS in the tab bar to open the register. Add items by tapping tiles, scanning barcodes, or typing in the search bar.") }
    public var image: Image? { Image(systemName: "cart") }

    public var rules: [Rule] {
        [
            #Rule(Self.appLaunched) { $0.donations.count >= 1 }
        ]
    }

    public var options: [any TipOption] {
        [Tips.MaxDisplayCount(1)]
    }

    public init() {}
}

/// "⌘N creates a new ticket faster" — shown once a hardware keyboard is detected
@available(iOS 17, *)
public struct NewTicketKeyboardTip: BrandTip {
    public static let hardwareKeyboardConnected = Event<TipEventPayload>(id: "hardware_keyboard_connected_for_new_ticket")

    public var title: Text { Text("New Ticket Shortcut") }
    public var message: Text? { Text("Press ⌘N anywhere in Tickets to create a new ticket instantly — no need to tap the + button.") }
    public var image: Image? { Image(systemName: "keyboard") }

    public var rules: [Rule] {
        [
            #Rule(Self.hardwareKeyboardConnected) { $0.donations.count >= 1 }
        ]
    }

    public var options: [any TipOption] {
        [Tips.MaxDisplayCount(1)]
    }

    public init() {}
}

/// "Tap Export in Reports to generate a CSV or PDF"
/// Shown the first time the user opens the Reports tab.
@available(iOS 17, *)
public struct ReportsExportTip: BrandTip {
    public static let reportsTabOpened = Event<TipEventPayload>(id: "reports_tab_opened_for_export_tip")

    public var title: Text { Text("Export Reports") }
    public var message: Text? { Text("Tap Export (top right) to save a CSV or PDF. Share via email, AirDrop, or Files.") }
    public var image: Image? { Image(systemName: "square.and.arrow.up") }

    public var rules: [Rule] {
        [
            #Rule(Self.reportsTabOpened) { $0.donations.count >= 1 }
        ]
    }

    public var options: [any TipOption] {
        [Tips.MaxDisplayCount(1)]
    }

    public init() {}
}
#endif // canImport(TipKit)
