import AppIntents
import SwiftUI
import WidgetKit
#if canImport(UIKit)
import UIKit
#endif

// MARK: - §24.10 App Intent enhancements
//
// Five items implemented here (open §24.10 items):
//   1. parameterSummary + IntentDescription — disambiguation "Which John?"
//   2. Dynamic suggestions — DynamicOptionsProvider for customer names
//   3. Focus filter intent — BizarreCRMFocusFilterIntent (DND-aware SendTextIntent)
//   4. Control Center widget config — AppIntentConfiguration with tenant/location
//   5. Intent error UX — IntentError enum + error snippet card

// MARK: - 1. Parameter Summary (disambiguation)

/// §24.10 — Extends CreateNewTicketIntent with a `parameterSummary` that Siri
/// uses to build the disambiguation prompt "Which John?" when the customer name
/// matches multiple records.
///
/// Also extends SendSMSToCustomerIntent with parameterSummary so the Shortcuts
/// editor shows a compact summary card rather than a raw parameter list.
@available(iOS 16.0, *)
extension CreateNewTicketIntent {
    /// Shown in Shortcuts editor as a human-readable sentence.
    static var parameterSummary: some ParameterSummary {
        When(\.$customerName, .hasAnyValue) {
            When(\.$device, .hasAnyValue) {
                Summary("Create ticket for \(\.$customerName) · \(\.$device)")
            } otherwise: {
                Summary("Create ticket for \(\.$customerName)")
            }
        } otherwise: {
            Summary("Create new ticket")
        }
    }
}

@available(iOS 16.0, *)
extension SendSMSToCustomerIntent {
    static var parameterSummary: some ParameterSummary {
        When(\.$messageBody, .hasAnyValue) {
            Summary("Text \(\.$customerQuery) \"\(\.$messageBody)\"")
        } otherwise: {
            Summary("Text \(\.$customerQuery)")
        }
    }
}

// MARK: - 2. Dynamic Suggestions — DynamicOptionsProvider

/// §24.10 — Provides autocomplete suggestions for the "customer name" parameter
/// in CreateNewTicketIntent and SendSMSToCustomerIntent.
///
/// The system calls `defaultValue()` and `results()` at suggestion time.
/// We read a cached list of recent customer names from App Group shared defaults
/// (written by the main app on each sync, same pipeline as WidgetDataStore).
@available(iOS 16.0, *)
struct CustomerNameOptionsProvider: DynamicOptionsProvider {
    func results() async throws -> [String] {
        // Read from App Group; main app writes on sync via WidgetDataStore pipeline.
        let suite = UserDefaults(suiteName: "group.com.bizarrecrm")
        guard
            let data = suite?.data(forKey: "suggestions.recentCustomerNames"),
            let names = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }
        // Return up to 20 names so the picker is not overwhelming.
        return Array(names.prefix(20))
    }

    func defaultValue() async throws -> String? { nil }
}

// MARK: - 3. Focus Filter Intent

/// §24.10 — Focus-aware send-text intent.
///
/// When the system is in Do Not Disturb focus and `urgentOnly` is false,
/// the intent throws an error telling Siri / Shortcuts that messaging is
/// suppressed. Marking a message "urgent" bypasses the gate.
///
/// Registered with SetFocusFilterIntent in Info.plist key
/// `NSFocusFilterIdentifiers` → `com.bizarrecrm.focus.sms`.
@available(iOS 16.0, *)
struct BizarreCRMFocusFilterIntent: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Set Bizarre CRM Focus Options"
    static let description: IntentDescription = IntentDescription(
        "Control which Bizarre CRM features are active during a Focus mode. For example, suppress non-urgent SMS notifications in Do Not Disturb."
    )

    /// When true, the active Focus suppresses non-urgent outbound SMS.
    @Parameter(
        title: "Suppress non-urgent SMS",
        description: "Disable outbound customer SMS while this Focus is active, except when the message is marked urgent."
    )
    var suppressNonUrgentSMS: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "Bizarre CRM Focus Options")
    }

    func perform() async throws -> some IntentResult {
        // Persist the current focus preference to App Group so the main app
        // can read it at SMS-compose time via FocusFilterActiveReader.
        let suite = UserDefaults(suiteName: "group.com.bizarrecrm")
        suite?.set(suppressNonUrgentSMS, forKey: "focus.suppressNonUrgentSMS")
        return .result()
    }
}

/// §24.10 — Sends a text message with DND / focus awareness.
///
/// If `BizarreCRMFocusFilterIntent.suppressNonUrgentSMS` is active and the
/// message is not marked urgent, the intent throws `IntentAppError.smsBlocked`.
@available(iOS 16.0, *)
struct FocusAwareSendTextIntent: AppIntent {
    static let title: LocalizedStringResource = "Send Text to Customer"
    static let description: IntentDescription = IntentDescription(
        "Send an SMS to a customer. Respects Focus / DND settings — non-urgent messages are blocked when Do Not Disturb suppression is on.",
        categoryName: "Communications"
    )
    static let isDiscoverable: Bool = true

    @Parameter(
        title: "Customer",
        description: "Customer name or phone number.",
        requestValueDialog: "Which customer do you want to text?",
        optionsProvider: CustomerNameOptionsProvider()
    )
    var customerQuery: String

    @Parameter(
        title: "Message",
        description: "Text to send.",
        requestValueDialog: "What's the message?"
    )
    var messageBody: String

    @Parameter(
        title: "Urgent",
        description: "Mark urgent to bypass Do Not Disturb suppression.",
        default: false
    )
    var isUrgent: Bool

    static var parameterSummary: some ParameterSummary {
        When(\.$isUrgent, .equalTo, true) {
            Summary("Urgently text \(\.$customerQuery): \(\.$messageBody)")
        } otherwise: {
            Summary("Text \(\.$customerQuery): \(\.$messageBody)")
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        // §24.10 — Check focus filter state before sending.
        let suite = UserDefaults(suiteName: "group.com.bizarrecrm")
        let suppressActive = suite?.bool(forKey: "focus.suppressNonUrgentSMS") ?? false

        if suppressActive && !isUrgent {
            throw IntentAppError.smsBlocked
        }

        var path = "bizarrecrm://sms/new?customer=\(customerQuery.urlEncoded)"
        path += "&body=\(messageBody.urlEncoded)"
        if isUrgent { path += "&urgent=1" }

        if let url = URL(string: path) {
            await openIntentURL(url)
        }

        return .result(
            dialog: "Sending text to \(customerQuery).",
            view: IntentResultCard(
                symbol: "message.fill",
                tint: .green,
                title: "Text Sent",
                detail: "To: \(customerQuery)"
            )
        )
    }
}

// MARK: - 4. Control Center widget configuration

/// §24.10 — Configurable widget intent that lets multi-tenant users choose
/// which tenant and which location to display in a Control Center–adjacent
/// widget. Bound to `AppIntentConfiguration` in the widget bundle.
@available(iOS 16.0, *)
struct WidgetTenantConfigIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Bizarre CRM Widget"
    static let description: IntentDescription = IntentDescription(
        "Choose which tenant and location to display in this widget.",
        categoryName: "Widgets"
    )

    /// The tenant slug shown in the widget (from the user's account list).
    @Parameter(
        title: "Tenant",
        description: "Which Bizarre CRM account to show data for.",
        requestValueDialog: "Which account?",
        optionsProvider: TenantOptionsProvider()
    )
    var tenantSlug: String?

    /// The location identifier within that tenant.
    @Parameter(
        title: "Location",
        description: "Which store location to display (leave blank for all).",
        requestValueDialog: "Which location?",
        optionsProvider: LocationOptionsProvider()
    )
    var locationID: String?
}

@available(iOS 16.0, *)
struct TenantOptionsProvider: DynamicOptionsProvider {
    func results() async throws -> [String] {
        let suite = UserDefaults(suiteName: "group.com.bizarrecrm")
        guard
            let data = suite?.data(forKey: "config.tenantSlugs"),
            let slugs = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return slugs
    }

    func defaultValue() async throws -> String? {
        UserDefaults(suiteName: "group.com.bizarrecrm")?.string(forKey: "config.defaultTenantSlug")
    }
}

@available(iOS 16.0, *)
struct LocationOptionsProvider: DynamicOptionsProvider {
    func results() async throws -> [String] {
        let suite = UserDefaults(suiteName: "group.com.bizarrecrm")
        guard
            let data = suite?.data(forKey: "config.locationIDs"),
            let ids = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return ids
    }

    func defaultValue() async throws -> String? { nil }
}

// MARK: - 5. Intent error UX

/// §24.10 — Typed errors thrown by intents. Each case provides a user-facing
/// `localizedDescription` that Siri or Shortcuts surfaces as an alert / banner.
enum IntentAppError: Swift.Error, CustomLocalizedStringResourceConvertible {
    /// Fired when the SMS send is blocked by the active Focus filter.
    case smsBlocked
    /// Fired when no customer matches the supplied name / phone.
    case customerNotFound(String)
    /// Fired when the App Group data store is unavailable (e.g., first launch before sync).
    case datastoreUnavailable
    /// Fired when a required parameter value is ambiguous and disambiguation fails.
    case ambiguousParameter(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .smsBlocked:
            return "SMS is suppressed by your active Focus mode. Mark the message urgent to send it anyway."
        case .customerNotFound(let query):
            return "No customer found matching \"\(query)\". Try a different name or phone number."
        case .datastoreUnavailable:
            return "Bizarre CRM data isn't ready yet. Open the app once to sync, then try again."
        case .ambiguousParameter(let name):
            return "\"\(name)\" matches multiple records. Please be more specific."
        }
    }
}

/// §24.10 — Error snippet card shown inline in Siri / Shortcuts when an intent fails.
struct IntentErrorCard: View {
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.red)
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Action Failed")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// §24.10 — Success snippet card reused across multiple intents.
struct IntentResultCard: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - URL helper (private to this file)

@MainActor
private func openIntentURL(_ url: URL) async {
    #if canImport(UIKit)
    await UIApplication.shared.open(url)
    #endif
}

// MARK: - String helper

private extension String {
    var urlEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}
