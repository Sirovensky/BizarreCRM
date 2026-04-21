// DesignSystem/Tips/TipsRegistrar.swift
//
// App-launch helper that configures TipKit for BizarreCRM.
// Call `TipsRegistrar.registerAll()` once during app startup
// (e.g., in `BizarreCRMApp.init()` or `AppServices.configure()`).
//
// §26 Sticky a11y tips (Phase 10)

#if canImport(TipKit)
import TipKit

/// Configures TipKit and registers BizarreCRM tip events at app launch.
///
/// Call once from the app entry point:
/// ```swift
/// TipsRegistrar.registerAll()
/// ```
@available(iOS 17, *)
public enum TipsRegistrar: Sendable {

    // MARK: - Public API

    /// Initializes the TipKit data store and configures global tip options.
    ///
    /// Safe to call multiple times — `Tips.configure` is idempotent.
    /// Must be called before any tip is displayed or any event is donated.
    public static func registerAll() {
        do {
            try Tips.configure([
                .displayFrequency(.immediate)
            ])
        } catch {
            // Tips.configure failure is non-fatal — app continues without tips.
#if DEBUG
            print("[TipsRegistrar] Tips.configure failed: \(error)")
#endif
        }
    }

    // MARK: - Event donation helpers

    /// Donates a "app launched" event to all launch-gated tips.
    /// Call once per app launch, after `registerAll()`.
    public static func donateAppLaunch() {
        Task {
            await CommandPaletteTip.appLaunched.donate(TipEventPayload())
            await PullToRefreshTip.appLaunched.donate(TipEventPayload())
        }
    }

    /// Donates a "tickets list viewed" event.
    /// Call from `TicketsListViewModel` `onAppear`.
    public static func donateTicketsListViewed() {
        Task { await SwipeToArchiveTip.ticketsListViewed.donate(TipEventPayload()) }
    }

    /// Donates a "list row viewed" event.
    /// Call from any list row `onAppear`.
    public static func donateListRowViewed() {
        Task { await ContextMenuTip.rowViewed.donate(TipEventPayload()) }
    }

    /// Donates a "SKU field viewed" event.
    /// Call from inventory / POS item form `onAppear`.
    public static func donateSkuFieldViewed() {
        Task { await ScanBarcodeTip.skuFieldViewed.donate(TipEventPayload()) }
    }
}
#endif // canImport(TipKit)
