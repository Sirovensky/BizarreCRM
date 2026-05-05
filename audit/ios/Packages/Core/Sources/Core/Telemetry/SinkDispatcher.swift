import Foundation

// §71 Privacy-first analytics — sink dispatcher

// MARK: — SinkDispatcher

/// Actor that fans out a single `AnalyticsEventPayload` to all registered sinks.
///
/// Usage:
/// ```swift
/// let dispatcher = SinkDispatcher(serverSink: serverSink, consent: consentManager)
/// await dispatcher.track(.appLaunched, properties: ["build": .string("42")])
/// ```
///
/// The dispatcher:
/// - Scrubs properties through `AnalyticsRedactor` before forwarding.
/// - Respects the user's consent preference (no-op if opted-out).
/// - Fans out to `TenantServerAnalyticsSink` and (in DEBUG) `LocalDebugSink`.
public actor SinkDispatcher {

    // MARK: — Dependencies

    private let serverSink: TenantServerAnalyticsSink
    private let consentManager: AnalyticsConsentManager
    private let sessionId: String
    private let tenantSlug: String
    private let appVersion: String

    // MARK: — Init

    public init(
        serverSink: TenantServerAnalyticsSink,
        consentManager: AnalyticsConsentManager,
        sessionId: String = UUID().uuidString,
        tenantSlug: String = "",
        appVersion: String = Platform.appVersion
    ) {
        self.serverSink = serverSink
        self.consentManager = consentManager
        self.sessionId = sessionId
        self.tenantSlug = tenantSlug
        self.appVersion = appVersion
    }

    // MARK: — Public API

    /// Track an event with optional properties.
    /// Properties are scrubbed before dispatch; PII keys are dropped.
    public func track(_ event: AnalyticsEvent, properties: [String: AnalyticsValue] = [:]) async {
        let allowed = await consentManager.shouldSendEvents
        guard allowed else { return }

        let scrubbed = AnalyticsRedactor.scrub(properties)
        let payload = AnalyticsEventPayload(
            event: event,
            properties: scrubbed,
            sessionId: sessionId,
            tenantSlug: tenantSlug,
            appVersion: appVersion
        )

        await serverSink.enqueue(payload)

#if DEBUG
        LocalDebugSink().log(payload)
#endif
    }

    /// Flush all sinks immediately (e.g. on app background).
    public func flush() async {
        await serverSink.flush()
    }
}
