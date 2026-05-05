import Testing
import Foundation
@testable import AuditLogs

// UserDefaults tests mutate shared state — run serially to avoid races.
@Suite("AuditLogAccessPolicy", .serialized)
struct AuditLogAccessPolicyTests {

    // MARK: - Role injection overload (no UserDefaults side effects)

    @Test func adminRole_isAllowed() {
        #expect(AuditLogAccessPolicy.canViewAuditLogs(role: "admin") == true)
    }

    @Test func ownerRole_isAllowed() {
        #expect(AuditLogAccessPolicy.canViewAuditLogs(role: "owner") == true)
    }

    @Test func technicianRole_isDenied() {
        #expect(AuditLogAccessPolicy.canViewAuditLogs(role: "technician") == false)
    }

    @Test func managerRole_isDenied() {
        #expect(AuditLogAccessPolicy.canViewAuditLogs(role: "manager") == false)
    }

    @Test func emptyRole_isDenied() {
        #expect(AuditLogAccessPolicy.canViewAuditLogs(role: "") == false)
    }

    @Test func unknownRole_isDenied() {
        #expect(AuditLogAccessPolicy.canViewAuditLogs(role: "viewer") == false)
    }

    // MARK: - Case insensitivity

    @Test func adminUppercase_isAllowed() {
        #expect(AuditLogAccessPolicy.canViewAuditLogs(role: "ADMIN") == true)
    }

    @Test func ownerMixedCase_isAllowed() {
        #expect(AuditLogAccessPolicy.canViewAuditLogs(role: "Owner") == true)
    }

    @Test func technicianUppercase_isDenied() {
        #expect(AuditLogAccessPolicy.canViewAuditLogs(role: "TECHNICIAN") == false)
    }

    // MARK: - UserDefaults-backed overload

    @Test func userDefaultsAdmin_isAllowed() {
        UserDefaults.standard.set("admin", forKey: "current_role")
        defer { UserDefaults.standard.removeObject(forKey: "current_role") }
        #expect(AuditLogAccessPolicy.canViewAuditLogs() == true)
    }

    @Test func userDefaultsOwner_isAllowed() {
        UserDefaults.standard.set("owner", forKey: "current_role")
        defer { UserDefaults.standard.removeObject(forKey: "current_role") }
        #expect(AuditLogAccessPolicy.canViewAuditLogs() == true)
    }

    @Test func userDefaultsAbsent_isDenied() {
        UserDefaults.standard.removeObject(forKey: "current_role")
        #expect(AuditLogAccessPolicy.canViewAuditLogs() == false)
    }

    @Test func userDefaultsTechnician_isDenied() {
        UserDefaults.standard.set("technician", forKey: "current_role")
        defer { UserDefaults.standard.removeObject(forKey: "current_role") }
        #expect(AuditLogAccessPolicy.canViewAuditLogs() == false)
    }
}
