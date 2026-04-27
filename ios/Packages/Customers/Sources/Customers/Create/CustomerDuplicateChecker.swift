import Foundation
import Observation
import Core
import Networking

// MARK: - §5.3 Duplicate Detection

/// Pure service: takes a phone/email and searches existing customers for
/// potential duplicates before a create call.
///
/// Matching rules (mirror Android `CustomerCreateViewModel.checkDuplicate`):
///  - Phone normalised: strip all non-digits, compare last 10.
///  - Email: lowercased exact match.
///
/// If the server `GET /customers?keyword=<phone>` returns a customer whose
/// normalised phone or email matches, it's a candidate.
public struct CustomerDuplicateChecker: Sendable {
    private let api: APIClient

    public init(api: APIClient) { self.api = api }

    /// Returns the first candidate that looks like a duplicate of the supplied
    /// (phone, email) pair, or nil if none found.
    ///
    /// Searches by email first (exact), then phone.
    /// Side-effects: one or two `GET /customers?keyword=` calls.
    public func findDuplicate(phone: String, email: String) async -> CustomerSummary? {
        // Email search
        let trimEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !trimEmail.isEmpty {
            if let result = try? await api.listCustomers(keyword: trimEmail).customers.first(where: {
                $0.email?.lowercased() == trimEmail
            }) {
                return result
            }
        }

        // Phone search
        let normalised = phone.filter(\.isNumber)
        let last10 = normalised.count >= 10 ? String(normalised.suffix(10)) : normalised
        guard last10.count >= 7 else { return nil }

        let results = (try? await api.listCustomers(keyword: last10).customers) ?? []
        return results.first { candidate in
            let cPhone = [candidate.mobile, candidate.phone]
                .compactMap { $0?.filter(\.isNumber) }
                .first { !$0.isEmpty } ?? ""
            let cLast10 = cPhone.count >= 10 ? String(cPhone.suffix(10)) : cPhone
            return !last10.isEmpty && cLast10 == last10
        }
    }
}

// MARK: - §5.3 Duplicate Detection ViewModel shim

/// Thin `@Observable` wrapper so Views can await the check reactively.
@MainActor
@Observable
public final class CustomerDuplicateCheckViewModel {
    public enum CheckState: Sendable {
        case idle
        case checking
        case found(CustomerSummary)
        case clear
    }

    public private(set) var checkState: CheckState = .idle

    @ObservationIgnored private let checker: CustomerDuplicateChecker

    public init(api: APIClient) {
        self.checker = CustomerDuplicateChecker(api: api)
    }

    /// Called just before form submission. Returns `true` if a duplicate was found
    /// (caller should pause and present the duplicate sheet).
    public func check(phone: String, email: String) async -> Bool {
        checkState = .checking
        if let dupe = await checker.findDuplicate(phone: phone, email: email) {
            checkState = .found(dupe)
            return true
        }
        checkState = .clear
        return false
    }

    public func dismiss() { checkState = .idle }
}
