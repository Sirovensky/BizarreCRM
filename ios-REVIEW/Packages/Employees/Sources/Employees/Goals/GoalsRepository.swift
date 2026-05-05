import Foundation
import Networking
import Core

// MARK: - GoalsRepository

public protocol GoalsRepository: Sendable {
    func listGoals(userId: String?, teamId: String?) async throws -> [Goal]
    func createGoal(_ req: CreateGoalRequest) async throws -> Goal
    func updateGoal(id: String, _ req: UpdateGoalRequest) async throws -> Goal
    func deleteGoal(id: String) async throws
}

// MARK: - GoalsRepositoryImpl

public actor GoalsRepositoryImpl: GoalsRepository {
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func listGoals(userId: String?, teamId: String?) async throws -> [Goal] {
        try await api.listGoals(userId: userId, teamId: teamId)
    }

    public func createGoal(_ req: CreateGoalRequest) async throws -> Goal {
        try await api.createGoal(req)
    }

    public func updateGoal(id: String, _ req: UpdateGoalRequest) async throws -> Goal {
        try await api.updateGoal(id: id, req)
    }

    public func deleteGoal(id: String) async throws {
        try await api.deleteGoal(id: id)
    }
}
