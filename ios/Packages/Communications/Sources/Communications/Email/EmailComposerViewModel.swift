import Foundation
import Observation
import Core
import Networking

// MARK: - EmailComposerViewModel

@MainActor
@Observable
public final class EmailComposerViewModel {

    // MARK: - Known chips

    public static let knownVars: [String] = [
        "{first_name}", "{ticket_no}", "{total}", "{due_date}",
        "{tech_name}", "{appointment_time}", "{shop_name}"
    ]

    // MARK: - Form fields

    public var toEmail: String
    public var subject: String
    public var body: String

    // MARK: - Cursor

    public var bodyCursorOffset: Int?

    // MARK: - State

    public private(set) var isSending: Bool = false
    public private(set) var errorMessage: String?
    public private(set) var didSend: Bool = false

    // MARK: - Derived

    public var isValid: Bool {
        !toEmail.trimmingCharacters(in: .whitespaces).isEmpty
            && !subject.trimmingCharacters(in: .whitespaces).isEmpty
            && !body.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Live HTML preview with sample data substituted.
    public var htmlPreview: String {
        guard !body.isEmpty else { return "" }
        return EmailRenderer.render(
            template: EmailTemplate(
                id: 0, name: "", subject: subject, htmlBody: body,
                plainBody: nil, category: .reminder, dynamicVars: []
            ),
            context: EmailRenderer.sampleContext
        ).html
    }

    // MARK: - Dependencies

    @ObservationIgnored private let api: APIClient

    public init(
        toEmail: String,
        prefillSubject: String = "",
        prefillBody: String = "",
        api: APIClient
    ) {
        self.toEmail = toEmail
        self.subject = prefillSubject
        self.body = prefillBody
        self.api = api
    }

    // MARK: - Chip insertion

    public func insertAtBodyCursor(_ token: String) {
        let insertIndex: Int
        if let offset = bodyCursorOffset, offset >= 0, offset <= body.count {
            insertIndex = offset
        } else {
            insertIndex = body.count
        }
        let idx = body.index(body.startIndex, offsetBy: insertIndex)
        body.insert(contentsOf: token, at: idx)
        bodyCursorOffset = insertIndex + token.count
    }

    // MARK: - Load template

    public func loadTemplate(_ template: EmailTemplate) {
        subject = template.subject
        body = template.htmlBody
        bodyCursorOffset = body.count
    }

    // MARK: - Send

    public func send() async {
        guard isValid, !isSending else { return }
        isSending = true
        errorMessage = nil
        defer { isSending = false }

        let rendered = EmailRenderer.render(
            template: EmailTemplate(
                id: 0, name: "", subject: subject, htmlBody: body,
                plainBody: nil, category: .reminder, dynamicVars: []
            ),
            context: [:]  // No context substitution on send — body already edited by user
        )

        do {
            _ = try await api.sendEmail(EmailSendRequest(
                to: toEmail,
                subject: rendered.subject,
                htmlBody: rendered.html,
                plainBody: rendered.plain
            ))
            didSend = true
        } catch {
            let appError = AppError.from(error)
            errorMessage = appError.errorDescription
            AppLog.ui.error("Email send failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
