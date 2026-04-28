import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - ReviewCadenceSettingsView
//
// §46.2 — Tenant-configurable performance review cadence.
// Settings → Team → Reviews → Cadence.
// Options: quarterly / semi-annual / annual.

public enum ReviewCadence: String, CaseIterable, Codable, Sendable {
    case quarterly   = "quarterly"
    case semiAnnual  = "semi_annual"
    case annual      = "annual"

    public var displayName: String {
        switch self {
        case .quarterly:  return "Quarterly (every 3 months)"
        case .semiAnnual: return "Semi-Annual (every 6 months)"
        case .annual:     return "Annual"
        }
    }
}

@MainActor
@Observable
public final class ReviewCadenceViewModel {
    public var cadence: ReviewCadence = .annual
    public private(set) var isLoading = false
    public private(set) var isSaving = false
    public private(set) var errorMessage: String?

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) { self.api = api }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            cadence = try await api.getReviewCadence()
        } catch {
            AppLog.ui.error("ReviewCadence load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await api.updateReviewCadence(cadence)
        } catch {
            AppLog.ui.error("ReviewCadence save failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}

public struct ReviewCadenceSettingsView: View {
    @State private var vm: ReviewCadenceViewModel

    public init(api: APIClient) {
        _vm = State(wrappedValue: ReviewCadenceViewModel(api: api))
    }

    public var body: some View {
        Form {
            Section {
                Picker("Review Cadence", selection: $vm.cadence) {
                    ForEach(ReviewCadence.allCases, id: \.self) { c in
                        Text(c.displayName).tag(c)
                    }
                }
                .pickerStyle(.inline)
                .onChange(of: vm.cadence) { _, _ in Task { await vm.save() } }
                .accessibilityLabel("Select performance review cadence")
            } header: {
                Text("Performance Review Frequency")
            } footer: {
                Text("Reviews will be scheduled automatically based on each employee's start date and the selected cadence.")
                    .font(.brandLabelSmall())
            }

            if let err = vm.errorMessage {
                Section { Text(err).foregroundStyle(.bizarreError) }
            }
        }
        .navigationTitle("Review Cadence")
        .task { await vm.load() }
    }
}

// MARK: - APIClient extension

extension APIClient {
    func getReviewCadence() async throws -> ReviewCadence {
        return try await get("/api/v1/settings/review-cadence", as: ReviewCadenceResp.self).cadence
    }

    func updateReviewCadence(_ cadence: ReviewCadence) async throws {
        _ = try await patch("/api/v1/settings/review-cadence", body: ReviewCadenceBody(cadence: cadence), as: ReviewCadenceResp.self)
    }
}

private struct ReviewCadenceResp: Decodable, Sendable {
    let cadence: ReviewCadence
}

private struct ReviewCadenceBody: Encodable, Sendable {
    let cadence: ReviewCadence
}
