import Foundation

// §4 — Ticket-domain convenience extensions on APIClient.
//
// This file contains thin wrappers for ticket endpoints that don't
// naturally belong in the per-resource Endpoints/ files because they
// combine multiple domain concepts (e.g. quick-assign which is just a
// filtered PUT /tickets/:id) or serve as the single source of truth
// for the endpoint path used by Tickets package view models.
//
// GROUNDING: every path here was verified against
//   packages/server/src/routes/tickets.routes.ts
//
// Paths confirmed:
//   POST   /api/v1/tickets              (line 861)
//   PUT    /api/v1/tickets/:id          (line 1804)
//   PATCH  /api/v1/tickets/:id/status   (line 2048)
//   POST   /api/v1/tickets/:id/notes    (line 2165)
//   GET    /api/v1/employees            (from EmployeesEndpoints.swift)

// NOTE: No new routes are invented here.  All wrappers delegate to existing
// APIClient extension methods defined in the Endpoints/ directory.

public extension APIClient {

    // MARK: - Employee list (used by assignee picker in Tickets)

    /// Fetches the full employee list for the assignee picker.
    /// Delegates to `EmployeesEndpoints.swift::listEmployees()`.
    /// Route: GET /api/v1/employees
    func ticketAssigneeCandidates() async throws -> [Employee] {
        try await listEmployees()
    }
}
