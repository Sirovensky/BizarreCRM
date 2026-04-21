import Foundation
import Observation
import Core
import Networking

// §5.5 Customer merge ViewModel — Phase 4 write flow.
// Drives three-step merge: pick candidate → diff fields → confirm.

/// The side whose field value wins for a given field.
public enum MergeFieldWinner: String, CaseIterable, Sendable {
    case primary
    case secondary
}

/// One row in the field-diff table.
public struct MergeFieldRow: Identifiable, Sendable {
    public let id: String          // field key e.g. "name"
    public let label: String
    public let primaryValue: String
    public let secondaryValue: String
    public var winner: MergeFieldWinner

    public var winnerValue: String {
        winner == .primary ? primaryValue : secondaryValue
    }
}

@MainActor
@Observable
public final class CustomerMergeViewModel {

    // MARK: - Inputs

    /// The customer whose record survives (keep).
    public let primary: CustomerDetail

    // MARK: - State

    public var candidateQuery: String = ""
    public var candidateResults: [CustomerSummary] = []
    public var selectedCandidate: CustomerSummary? = nil

    public var fieldRows: [MergeFieldRow] = []

    public private(set) var isSearching: Bool = false
    public private(set) var isMerging: Bool = false
    public private(set) var errorMessage: String? = nil
    public private(set) var conflictMessage: String? = nil
    public private(set) var mergeComplete: Bool = false

    // MARK: - Dependencies

    @ObservationIgnored private let api: APIClient

    // MARK: - Init

    public init(api: APIClient, primary: CustomerDetail) {
        self.api = api
        self.primary = primary
    }

    // MARK: - Candidate search

    public func searchCandidates() async {
        let q = candidateQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { candidateResults = []; return }
        isSearching = true
        defer { isSearching = false }
        do {
            let response = try await api.listCustomers(keyword: q)
            // Exclude the primary from results.
            candidateResults = response.customers.filter { $0.id != primary.id }
        } catch {
            candidateResults = []
        }
    }

    public func selectCandidate(_ candidate: CustomerSummary) async {
        selectedCandidate = candidate
        await buildFieldRows(secondary: candidate)
    }

    // MARK: - Field rows

    private func buildFieldRows(secondary: CustomerSummary) async {
        let primaryName = primary.displayName
        let secondaryName = secondary.displayName

        let primaryPhone = [primary.mobile, primary.phone].compactMap { $0?.isEmpty == false ? $0 : nil }.first ?? ""
        let secondaryPhone = [secondary.mobile, secondary.phone].compactMap { $0?.isEmpty == false ? $0 : nil }.first ?? ""

        let primaryEmail = primary.email ?? ""
        let secondaryEmail = secondary.email ?? ""

        let primaryAddress = primary.addressLine ?? ""
        let secondaryAddress = [secondary.city, secondary.state].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: ", ")

        let primaryNotes = primary.comments ?? ""

        fieldRows = [
            MergeFieldRow(id: "name",    label: "Name",    primaryValue: primaryName,    secondaryValue: secondaryName,    winner: .primary),
            MergeFieldRow(id: "phone",   label: "Phone",   primaryValue: primaryPhone,   secondaryValue: secondaryPhone,   winner: .primary),
            MergeFieldRow(id: "email",   label: "Email",   primaryValue: primaryEmail,   secondaryValue: secondaryEmail,   winner: .primary),
            MergeFieldRow(id: "address", label: "Address", primaryValue: primaryAddress, secondaryValue: secondaryAddress, winner: .primary),
            MergeFieldRow(id: "notes",   label: "Notes",   primaryValue: primaryNotes,   secondaryValue: "",               winner: .primary),
        ]
    }

    public func setWinner(_ winner: MergeFieldWinner, forRowId id: String) {
        guard let index = fieldRows.firstIndex(where: { $0.id == id }) else { return }
        fieldRows[index] = MergeFieldRow(
            id: fieldRows[index].id,
            label: fieldRows[index].label,
            primaryValue: fieldRows[index].primaryValue,
            secondaryValue: fieldRows[index].secondaryValue,
            winner: winner
        )
    }

    // MARK: - Merge

    public func performMerge() async {
        guard let candidate = selectedCandidate, !isMerging else { return }
        isMerging = true
        errorMessage = nil
        conflictMessage = nil
        defer { isMerging = false }

        let prefs = CustomerMergeFieldPreferences(
            name:    fieldRows.first(where: { $0.id == "name" })?.winner.rawValue    ?? "primary",
            phone:   fieldRows.first(where: { $0.id == "phone" })?.winner.rawValue   ?? "primary",
            email:   fieldRows.first(where: { $0.id == "email" })?.winner.rawValue   ?? "primary",
            address: fieldRows.first(where: { $0.id == "address" })?.winner.rawValue ?? "primary",
            notes:   fieldRows.first(where: { $0.id == "notes" })?.winner.rawValue   ?? "primary"
        )

        let req = CustomerMergeRequest(
            primaryId: primary.id,
            secondaryId: candidate.id,
            fieldPreferences: prefs
        )

        do {
            _ = try await api.mergeCustomers(req)
            mergeComplete = true
        } catch {
            // Check both AppError.conflict and APITransportError HTTP 409.
            if let appErr = error as? AppError, case .conflict(let reason) = appErr {
                conflictMessage = reason ?? "This customer has an open ticket — resolve it first."
            } else if let transport = error as? APITransportError,
                      case .httpStatus(409, let msg) = transport {
                conflictMessage = msg ?? "This customer has an open ticket — resolve it first."
            } else {
                errorMessage = AppError.from(error).localizedDescription
            }
        }
    }
}
