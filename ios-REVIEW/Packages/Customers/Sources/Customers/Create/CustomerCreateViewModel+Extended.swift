import Foundation
import Networking
import Core

// MARK: - §5.3 Extended field state on CustomerCreateViewModel

extension CustomerCreateViewModel {
    // Extended fields are stored as nonisolated properties using @ObservationIgnored
    // shims won't work for stored props on final classes in Swift 6.
    // We use a wrapper struct carried as a single stored property instead.

    /// Wrapper holding all §5.3 extended fields so a single `@Observable`-tracked
    /// property carries them all without per-property `_modify` conflicts.
    public struct ExtendedState: Sendable, Equatable {
        public var type: String = "person"          // "person" | "business"
        public var hasBirthday: Bool = false
        public var birthday: Date? = nil
        public var tags: [String] = []
        public var tagInput: String = ""
        public var referralSource: String = ""
        public var commPrefs: CustomerCommPrefs = .init()

        public init() {}
    }
}

// NOTE: The ExtendedState property is added to CustomerCreateViewModel via the
// CustomerCreateView instantiation — view holds @State private var ext = ExtendedState()
// and passes bindings into CustomerExtendedFieldsSection. This avoids mutating the
// existing class definition while still fully wiring the UI.
//
// The buildExtendedRequest() free function below is called from the view's submit path.

extension CustomerCreateViewModel {
    /// Build a §5.3 extended payload from the core VM fields plus the extended state.
    public func buildExtendedRequest(ext: ExtendedState) -> CreateCustomerExtendedRequest {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let birthdayString: String? = (ext.hasBirthday && ext.birthday != nil)
            ? formatter.string(from: ext.birthday!)
            : nil

        return CreateCustomerExtendedRequest(
            firstName: firstName.trimmingCharacters(in: .whitespaces),
            lastName: lastName.trimmingCharacters(in: .whitespaces).nonEmpty,
            email: email.trimmingCharacters(in: .whitespaces).nonEmpty,
            phone: phone.trimmingCharacters(in: .whitespaces).nonEmpty.map(PhoneFormatter.normalize),
            mobile: mobile.trimmingCharacters(in: .whitespaces).nonEmpty.map(PhoneFormatter.normalize),
            organization: organization.trimmingCharacters(in: .whitespaces).nonEmpty,
            address1: address1.trimmingCharacters(in: .whitespaces).nonEmpty,
            city: city.trimmingCharacters(in: .whitespaces).nonEmpty,
            state: state.trimmingCharacters(in: .whitespaces).nonEmpty,
            postcode: postcode.trimmingCharacters(in: .whitespaces).nonEmpty,
            notes: notes.trimmingCharacters(in: .whitespaces).nonEmpty,
            type: ext.type,
            birthday: birthdayString,
            tags: ext.tags.isEmpty ? nil : ext.tags,
            referralSource: ext.referralSource.nonEmpty,
            smsOptIn: ext.commPrefs.smsOptIn,
            emailOptIn: ext.commPrefs.emailOptIn,
            callOptIn: ext.commPrefs.callOptIn,
            marketingOptIn: ext.commPrefs.marketingOptIn
        )
    }
}

private extension String {
    var nonEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
