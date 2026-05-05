import Foundation
import Networking
import Core

// MARK: - FocusFilterEndpoints

/// Server-side persistence for `FocusFilterDescriptor`.
/// Endpoint: `GET/PUT /notifications/focus-policies`.
/// The server stores the JSON blob per user; iOS sends the full descriptor
/// on save and fetches it on app launch / settings open.
public struct FocusFilterEndpoints: Sendable {

    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    // MARK: - Fetch

    /// Fetch the stored focus-filter descriptor for the current user.
    public func fetchDescriptor() async throws -> FocusFilterDescriptor {
        let dto = try await api.get(
            "/notifications/focus-policies",
            as: FocusDescriptorDTO.self
        )
        return dto.toDomain()
    }

    // MARK: - Persist

    /// Persist the descriptor (full replace).
    public func saveDescriptor(_ descriptor: FocusFilterDescriptor) async throws {
        let dto = FocusDescriptorDTO(from: descriptor)
        let _: EmptyBodyResponse = try await api.put(
            "/notifications/focus-policies",
            body: dto,
            as: EmptyBodyResponse.self
        )
    }
}

// MARK: - DTO

struct FocusDescriptorDTO: Codable, Sendable {
    let policies: [FocusPolicyDTO]

    init(from descriptor: FocusFilterDescriptor) {
        policies = descriptor.policies.values.map { FocusPolicyDTO(from: $0) }
    }

    func toDomain() -> FocusFilterDescriptor {
        let mapped = policies.compactMap { dto -> (FocusMode, FocusFilterPolicy)? in
            guard let mode = FocusMode(rawValue: dto.focusMode) else { return nil }
            let cats = Set(dto.allowedCategories.compactMap { EventCategory(rawValue: $0) })
            let policy = FocusFilterPolicy(
                focusMode: mode,
                allowedCategories: cats,
                allowCriticalOverride: dto.allowCriticalOverride
            )
            return (mode, policy)
        }
        return FocusFilterDescriptor(policies: Dictionary(uniqueKeysWithValues: mapped))
    }
}

struct FocusPolicyDTO: Codable, Sendable {
    let focusMode: String
    let allowedCategories: [String]
    let allowCriticalOverride: Bool

    init(from policy: FocusFilterPolicy) {
        self.focusMode = policy.focusMode.rawValue
        self.allowedCategories = policy.allowedCategories.map(\.rawValue)
        self.allowCriticalOverride = policy.allowCriticalOverride
    }
}

private struct EmptyBodyResponse: Decodable, Sendable {}
