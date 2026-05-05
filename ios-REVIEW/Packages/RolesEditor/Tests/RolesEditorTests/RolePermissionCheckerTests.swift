import Testing
@testable import RolesEditor

// MARK: - RolePermissionCheckerTests

@Suite("RolePermissionChecker")
struct RolePermissionCheckerTests {

    private let adminRole = Role(
        id: "admin",
        name: "Admin",
        capabilities: ["tickets.view.any", "tickets.delete", "customers.export", "audit.view.all"]
    )

    private let viewerRole = Role(
        id: "viewer",
        name: "Viewer",
        capabilities: ["tickets.view.any", "customers.view"]
    )

    // MARK: has

    @Test("has returns true when capability is present")
    func hasReturnsTrue() {
        #expect(RolePermissionChecker.has(capability: "tickets.delete", role: adminRole))
    }

    @Test("has returns false when capability is absent")
    func hasReturnsFalse() {
        #expect(!RolePermissionChecker.has(capability: "danger.tenant.delete", role: adminRole))
    }

    @Test("has returns false for empty role")
    func hasReturnsFalseForEmptyRole() {
        let emptyRole = Role(id: "empty", name: "Empty", capabilities: [])
        #expect(!RolePermissionChecker.has(capability: "tickets.view.any", role: emptyRole))
    }

    // MARK: hasAll

    @Test("hasAll returns true when all present")
    func hasAllReturnsTrue() {
        let caps = ["tickets.view.any", "tickets.delete"]
        #expect(RolePermissionChecker.hasAll(capabilities: caps, role: adminRole))
    }

    @Test("hasAll returns false when one missing")
    func hasAllReturnsFalseWhenOneMissing() {
        let caps = ["tickets.view.any", "tickets.delete", "sms.broadcast"]
        #expect(!RolePermissionChecker.hasAll(capabilities: caps, role: adminRole))
    }

    @Test("hasAll returns true for empty list")
    func hasAllReturnsTrueForEmptyList() {
        #expect(RolePermissionChecker.hasAll(capabilities: [], role: viewerRole))
    }

    // MARK: hasAny

    @Test("hasAny returns true when at least one matches")
    func hasAnyReturnsTrue() {
        let caps = ["sms.broadcast", "customers.export"]
        #expect(RolePermissionChecker.hasAny(capabilities: caps, role: adminRole))
    }

    @Test("hasAny returns false when none match")
    func hasAnyReturnsFalse() {
        let caps = ["sms.broadcast", "danger.tenant.delete"]
        #expect(!RolePermissionChecker.hasAny(capabilities: caps, role: viewerRole))
    }

    @Test("hasAny returns false for empty list")
    func hasAnyReturnsFalseForEmptyList() {
        #expect(!RolePermissionChecker.hasAny(capabilities: [], role: adminRole))
    }

    // MARK: intersection

    @Test("intersection returns overlapping capabilities")
    func intersectionReturnsOverlap() {
        let caps = ["tickets.view.any", "sms.broadcast"]
        let result = RolePermissionChecker.intersection(capabilities: caps, role: adminRole)
        #expect(result == ["tickets.view.any"])
    }

    @Test("intersection returns empty when no overlap")
    func intersectionReturnsEmpty() {
        let caps = ["danger.tenant.delete", "data.wipe"]
        let result = RolePermissionChecker.intersection(capabilities: caps, role: viewerRole)
        #expect(result.isEmpty)
    }

    // MARK: missing

    @Test("missing returns absent capabilities")
    func missingReturnsMissingCaps() {
        let caps = ["tickets.view.any", "danger.tenant.delete"]
        let result = RolePermissionChecker.missing(capabilities: caps, role: adminRole)
        #expect(result == ["danger.tenant.delete"])
    }

    @Test("missing returns empty when all present")
    func missingReturnsEmptyWhenAllPresent() {
        let caps = ["tickets.view.any", "customers.view"]
        let result = RolePermissionChecker.missing(capabilities: caps, role: viewerRole)
        #expect(result.isEmpty)
    }

    // MARK: Integration with presets

    @Test("Owner role has all capabilities via checker")
    func ownerHasAllCaps() {
        let ownerRole = RolePresets.owner.makeRole()
        for cap in CapabilityCatalog.all {
            #expect(RolePermissionChecker.has(capability: cap.id, role: ownerRole),
                    "Owner missing: \(cap.id)")
        }
    }

    @Test("Viewer cannot send SMS or delete tickets")
    func viewerCannotSendSmsOrDeleteTickets() {
        let viewerPreset = RolePresets.viewer.makeRole()
        #expect(!RolePermissionChecker.has(capability: "sms.send", role: viewerPreset))
        #expect(!RolePermissionChecker.has(capability: "tickets.delete", role: viewerPreset))
    }
}
