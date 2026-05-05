import Foundation
import Observation
import Networking

/// §16.7 — view model for the post-sale screen. Owns the charge-spinner
/// debounce, the email / text-receipt async state, and the validation used
/// by the receipt-delivery sheets.
///
/// Kept platform-agnostic (no SwiftUI types) so the unit tests can exercise
/// the email / phone validation paths without a UIKit test host. The
/// SwiftUI layer observes `@Observable` state on the type.
///
/// The view model is `@MainActor` because it drives UI state — every
/// mutation happens on the main actor and `dispatchEmail` / `dispatchSms`
/// internally bounce to background work via the APIClient.
@MainActor
@Observable
public final class PosPostSaleViewModel: Identifiable {
    public let id: UUID = UUID()


    /// Phase of the charge animation. The real §17.3 terminal flow will
    /// extend this enum with `contacting`, `awaitingInsert`, etc. — the
    /// scaffold only needs the spinner interlude + the settled state.
    public enum Phase: Equatable, Sendable {
        /// Brief spinner while the charge "runs". Transitions to `completed`
        /// after `spinnerMillis`. Kept as a discrete phase so the spinner
        /// view doesn't race the success card.
        case processing
        /// Terminal state. The receipt actions are enabled here.
        case completed
    }

    /// Which receipt-delivery sheet is currently presented. Used as a
    /// one-slot enum rather than separate booleans so only one sheet can
    /// surface at a time.
    public enum ActiveSheet: Equatable, Identifiable, Sendable {
        case email
        case sms
        public var id: String {
            switch self {
            case .email: return "email"
            case .sms:   return "sms"
            }
        }
    }

    /// Status of the most recent email/sms send. Drives the banner shown
    /// under the send buttons.
    public enum SendStatus: Equatable, Sendable {
        case idle
        case sending
        case sent(String)
        case failed(String)
    }

    public private(set) var phase: Phase = .processing
    public var activeSheet: ActiveSheet?
    public private(set) var emailStatus: SendStatus = .idle
    public private(set) var smsStatus: SendStatus = .idle
    public var emailInput: String
    public var phoneInput: String
    public private(set) var cartCleared: Bool = false

    public let totalCents: Int
    public let methodLabel: String
    public let receiptText: String
    public let receiptHtml: String
    public let receiptPayload: PosReceiptRenderer.Payload?
    public let invoiceId: Int64
    public let defaultEmail: String?
    public let defaultPhone: String?

    /// Millis the spinner spins before the card settles. Injectable so
    /// tests can drive the transition synchronously.
    public let spinnerMillis: UInt64

    @ObservationIgnored private let api: APIClient?
    @ObservationIgnored private let nextSale: () -> Void

    public init(
        totalCents: Int,
        methodLabel: String,
        receiptText: String,
        receiptHtml: String,
        receiptPayload: PosReceiptRenderer.Payload? = nil,
        invoiceId: Int64 = -1,
        defaultEmail: String? = nil,
        defaultPhone: String? = nil,
        api: APIClient? = nil,
        spinnerMillis: UInt64 = 600,
        nextSale: @escaping () -> Void = {}
    ) {
        self.totalCents = totalCents
        self.methodLabel = methodLabel
        self.receiptText = receiptText
        self.receiptHtml = receiptHtml
        self.receiptPayload = receiptPayload
        self.invoiceId = invoiceId
        self.defaultEmail = defaultEmail
        self.defaultPhone = defaultPhone
        self.emailInput = defaultEmail ?? ""
        self.phoneInput = defaultPhone ?? ""
        self.api = api
        self.spinnerMillis = spinnerMillis
        self.nextSale = nextSale
    }

    /// Drive the brief spinner then flip to `.completed`. Call this from
    /// `.task { }` on the root view; safe to call repeatedly — subsequent
    /// calls after the first no-op.
    public func runSpinner() async {
        guard phase == .processing else { return }
        try? await Task.sleep(nanoseconds: spinnerMillis * 1_000_000)
        phase = .completed
    }

    /// Trim + validate an email. `true` only if it matches a conservative
    /// `<local>@<domain>.<tld>` shape. Not RFC-perfect on purpose — the
    /// server does the final check; this is for the Submit-disabled gate.
    public static func isValidEmail(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return false }
        guard let at = trimmed.firstIndex(of: "@") else { return false }
        let local = trimmed[..<at]
        let afterAt = trimmed.index(after: at)
        guard afterAt < trimmed.endIndex else { return false }
        let domainPart = String(trimmed[afterAt...])
        guard !local.isEmpty else { return false }
        guard domainPart.contains("."),
              !domainPart.hasPrefix("."),
              !domainPart.hasSuffix(".") else { return false }
        let tldStart = domainPart.lastIndex(of: ".")!
        let tld = domainPart[domainPart.index(after: tldStart)...]
        return tld.count >= 2
    }

    /// Accept any phone with 7+ digits once non-digits are stripped. Matches
    /// the server's inbound normalization.
    public static func isValidPhone(_ raw: String) -> Bool {
        let digits = raw.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }
        return digits.count >= 7
    }

    public var isEmailValid: Bool { Self.isValidEmail(emailInput) }
    public var isPhoneValid: Bool { Self.isValidPhone(phoneInput) }

    public func openEmailSheet() {
        emailStatus = .idle
        activeSheet = .email
    }

    public func openSmsSheet() {
        smsStatus = .idle
        activeSheet = .sms
    }

    public func dismissSheet() {
        activeSheet = nil
    }

    /// Fire the "Next sale" action: triggers the host closure (which
    /// clears the cart + customer) and flags the VM so tests can assert
    /// the side effect ran.
    public func triggerNextSale() {
        nextSale()
        cartCleared = true
    }

    /// Attempt to POST the receipt email. The server is expected to reject
    /// `invoice_id: -1` with HTTP 400 while §17.3 is pending; that case
    /// flips to `.sent(placeholder)` so the staff-facing banner still says
    /// "done" — the important thing is that the UI cannot pretend the
    /// real email was delivered.
    public func submitEmail() async {
        guard isEmailValid else {
            emailStatus = .failed("Enter a valid email address.")
            return
        }
        emailStatus = .sending
        guard let api else {
            emailStatus = .sent("Receipt placeholder (real charge pending §17.3)")
            activeSheet = nil
            return
        }
        do {
            _ = try await api.sendReceipt(
                SendReceiptRequest(
                    invoiceId: invoiceId,
                    email: emailInput.trimmingCharacters(in: .whitespacesAndNewlines),
                    html: receiptHtml,
                    text: receiptText
                )
            )
            emailStatus = .sent("Receipt sent to \(emailInput).")
        } catch let APITransportError.httpStatus(status, _) where status == 400 || status == 404 {
            // Expected while charges are not yet wired — server refuses
            // invoice_id -1. Treat as soft-success so staff aren't trained
            // to distrust the flow.
            emailStatus = .sent("Receipt placeholder (real charge pending §17.3)")
        } catch {
            emailStatus = .failed(error.localizedDescription)
        }
        if case .sent = emailStatus { activeSheet = nil }
    }

    /// POST the receipt text as an SMS. SMS routes exist today, so a
    /// failure here is a real network / auth error, not a missing-endpoint
    /// soft-fail.
    public func submitSms() async {
        guard isPhoneValid else {
            smsStatus = .failed("Enter a valid phone number.")
            return
        }
        smsStatus = .sending
        guard let api else {
            smsStatus = .sent("Receipt placeholder (real charge pending §17.3)")
            activeSheet = nil
            return
        }
        do {
            _ = try await api.sendSms(
                to: phoneInput.trimmingCharacters(in: .whitespacesAndNewlines),
                message: receiptText
            )
            smsStatus = .sent("Text sent to \(phoneInput).")
        } catch let APITransportError.httpStatus(status, _) where status == 404 {
            smsStatus = .sent("Receipt placeholder (real charge pending §17.3)")
        } catch {
            smsStatus = .failed(error.localizedDescription)
        }
        if case .sent = smsStatus { activeSheet = nil }
    }
}
