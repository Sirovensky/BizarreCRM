import AppIntents
import WidgetKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - §24.8 Reply to SMS inline widget (typing button)
//
// True inline text-input inside a widget is not possible in WidgetKit
// (widgets cannot host a `TextField`). The best-practice pattern for
// inline-ish SMS reply from a widget is:
//
//   1. Widget shows the latest SMS snippet + a "Reply" button.
//   2. Button tap fires `SMSQuickReplyIntent` which opens the app's SMS composer
//      deep-linked to the thread, pre-focused on the input field.
//
// This gives the user a one-tap path to reply without having to navigate manually,
// while keeping the interaction model safe and native.
//
// iOS 17+ note: if Apple ever allows `TextInputIntent` in widgets, this intent
// can be upgraded to stay fully in-widget.

// MARK: - SMSQuickReplyWidgetIntent

/// §24.8 — Opens the SMS composer for a specific thread from the widget.
/// One-tap path: user sees unread SMS in widget, taps "Reply", app opens
/// to the thread with keyboard raised.
@available(iOS 16.0, *)
struct SMSQuickReplyWidgetIntent: AppIntent {

    static var title: LocalizedStringResource = "Reply to SMS"
    static var description: IntentDescription = IntentDescription(
        "Open the SMS conversation in BizarreCRM to send a quick reply.",
        categoryName: "Communications"
    )
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Thread ID", description: "The SMS thread to open.")
    var threadId: String

    @Parameter(title: "Customer Name", description: "Customer display name shown in the widget.")
    var customerName: String

    init() {
        self.threadId = ""
        self.customerName = ""
    }

    init(threadId: String, customerName: String) {
        self.threadId = threadId
        self.customerName = customerName
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let urlString = "bizarrecrm://sms/\(threadId)?focus=reply"
        await openURL(urlString)
        return .result(dialog: "Opening conversation with \(customerName).")
    }
}

// MARK: - UnreadSMSEntry (App Group–backed widget data)

/// Snapshot of the most-recent unread SMS for the widget timeline.
/// Written by the main app on sync; read by the widget extension.
public struct UnreadSMSEntry: Codable, Sendable, Identifiable {
    public let id: String          // thread ID
    public let customerName: String
    public let preview: String     // truncated last message body
    public let unreadCount: Int
    public let receivedAt: Date

    public init(
        id: String,
        customerName: String,
        preview: String,
        unreadCount: Int,
        receivedAt: Date
    ) {
        self.id = id
        self.customerName = customerName
        self.preview = preview
        self.unreadCount = unreadCount
        self.receivedAt = receivedAt
    }
}

// MARK: - SMSUnreadWidgetView

/// Small widget view showing the top unread SMS + a "Reply" action button.
/// Suitable for the Small (2×2) and Accessory Rectangular family sizes.
@available(iOS 17.0, *)
struct SMSUnreadWidgetView: View {

    let entry: UnreadSMSEntry?

    var body: some View {
        if let entry {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "message.fill")
                        .foregroundStyle(.blue)
                        .font(.caption)
                        .accessibilityHidden(true)
                    Text("Unread SMS")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if entry.unreadCount > 1 {
                        Text("+\(entry.unreadCount - 1)")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }

                Text(entry.customerName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)

                Text(entry.preview)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Spacer(minLength: 0)

                // §24.8 — Reply button that opens the SMS composer.
                Button(
                    intent: SMSQuickReplyWidgetIntent(
                        threadId: entry.id,
                        customerName: entry.customerName
                    )
                ) {
                    Label("Reply", systemImage: "arrowshape.turn.up.left.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reply to \(entry.customerName)")
                .accessibilityHint("Opens the SMS conversation in BizarreCRM")
            }
            .padding(10)
            .containerBackground(.fill.tertiary, for: .widget)
        } else {
            noMessageView
        }
    }

    private var noMessageView: some View {
        VStack(spacing: 6) {
            Image(systemName: "message")
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No unread SMS")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(.fill.tertiary, for: .widget)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No unread SMS messages")
    }
}

// MARK: - App Group data bridge

/// Reads/writes `UnreadSMSEntry` from the shared App Group so the widget
/// can show fresh data without a live app process.
public enum UnreadSMSWidgetStore {

    private static let key = "widget.unreadSMS.latest"
    private static let defaults = UserDefaults(suiteName: "group.com.bizarrecrm") ?? .standard

    /// Called from the main app on sync-complete to publish the latest unread thread.
    public static func write(_ entry: UnreadSMSEntry?) {
        guard let entry else {
            defaults.removeObject(forKey: key)
            WidgetCenter.shared.reloadTimelines(ofKind: "SMSUnreadWidget")
            return
        }
        if let data = try? JSONEncoder().encode(entry) {
            defaults.set(data, forKey: key)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "SMSUnreadWidget")
    }

    /// Called from the widget timeline provider.
    public static func read() -> UnreadSMSEntry? {
        guard let data = defaults.data(forKey: key),
              let entry = try? JSONDecoder().decode(UnreadSMSEntry.self, from: data)
        else { return nil }
        return entry
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
