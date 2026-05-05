import Testing
@testable import RolesEditor

// MARK: - RolePresetCatalogTests
//
// §47 Roles Capability Presets — tests for RolePresetDescriptor value type
// and the six canonical presets in RolePresetCatalog.

@Suite("RolePresetCatalog")
struct RolePresetCatalogTests {

    // MARK: - Catalog completeness

    @Test("catalog contains exactly 6 presets")
    func catalogHasSixPresets() {
        #expect(RolePresetCatalog.all.count == 6)
    }

    @Test("all catalog ids are unique")
    func catalogIdsAreUnique() {
        let ids = RolePresetCatalog.all.map(\.id)
        #expect(ids.count == Set(ids).count)
    }

    @Test("all catalog entries have non-empty fields")
    func catalogFieldsNonEmpty() {
        for preset in RolePresetCatalog.all {
            #expect(!preset.id.isEmpty,          "id empty for \(preset.name)")
            #expect(!preset.name.isEmpty,        "name empty for \(preset.id)")
            #expect(!preset.description.isEmpty, "description empty for \(preset.id)")
            #expect(!preset.capabilities.isEmpty, "capabilities empty for \(preset.id)")
        }
    }

    @Test("all preset capability ids exist in CapabilityCatalog")
    func capabilityIdsAreValid() {
        let validIds = Set(CapabilityCatalog.all.map(\.id))
        for preset in RolePresetCatalog.all {
            for capId in preset.capabilities {
                #expect(validIds.contains(capId),
                        "Unknown capability '\(capId)' in preset '\(preset.name)'")
            }
        }
    }

    // MARK: - Named presets present

    @Test("Owner preset exists and has full capability set")
    func ownerExistsAndHasAllCaps() {
        let allIds = Set(CapabilityCatalog.all.map(\.id))
        #expect(RolePresetCatalog.owner.capabilities == allIds)
        #expect(RolePresetCatalog.owner.name == "Owner")
    }

    @Test("Admin preset exists and has full capability set")
    func adminExistsAndHasAllCaps() {
        let allIds = Set(CapabilityCatalog.all.map(\.id))
        #expect(RolePresetCatalog.admin.capabilities == allIds)
        #expect(RolePresetCatalog.admin.name == "Admin")
    }

    @Test("Manager preset excludes danger and billing caps")
    func managerExcludesDangerCaps() {
        let caps = RolePresetCatalog.manager.capabilities
        #expect(!caps.contains("danger.tenant.delete"), "Manager must not have tenant.delete")
        #expect(!caps.contains("settings.billing"),     "Manager must not have settings.billing")
        #expect(!caps.contains("danger.data.wipe"),     "Manager must not have danger.data.wipe")
        #expect(!caps.contains("data.wipe"),            "Manager must not have data.wipe")
    }

    @Test("Manager preset retains most daily-ops capabilities")
    func managerHasMostCaps() {
        // Manager should be the largest subset below Owner/Admin
        let allCount = CapabilityCatalog.all.count
        let managerCount = RolePresetCatalog.manager.capabilities.count
        #expect(managerCount > allCount / 2, "Manager should have more than half of capabilities")
    }

    @Test("Technician preset includes required repair capabilities")
    func technicianHasRepairCaps() {
        let caps = RolePresetCatalog.technician.capabilities
        #expect(caps.contains("tickets.view.any"))
        #expect(caps.contains("tickets.edit"))
        #expect(caps.contains("inventory.adjust"))
        #expect(caps.contains("sms.send"))
    }

    @Test("Technician preset excludes admin and financial capabilities")
    func technicianLacksAdminCaps() {
        let caps = RolePresetCatalog.technician.capabilities
        #expect(!caps.contains("settings.edit.roles"))
        #expect(!caps.contains("invoices.void"))
        #expect(!caps.contains("invoices.refund"))
        #expect(!caps.contains("danger.tenant.delete"))
    }

    @Test("Cashier preset includes POS capabilities")
    func cashierHasPosCaps() {
        let caps = RolePresetCatalog.cashier.capabilities
        #expect(caps.contains("invoices.create"))
        #expect(caps.contains("invoices.payment.accept"))
        #expect(caps.contains("customers.create"))
    }

    @Test("Cashier preset does not include refund or void")
    func cashierCannotRefundOrVoid() {
        let caps = RolePresetCatalog.cashier.capabilities
        #expect(!caps.contains("invoices.refund"))
        #expect(!caps.contains("invoices.void"))
        #expect(!caps.contains("invoices.payment.refund"))
    }

    @Test("Read-Only preset has no write capabilities")
    func readOnlyHasNoWriteCaps() {
        let caps = RolePresetCatalog.readOnly.capabilities
        #expect(!caps.contains("tickets.create"))
        #expect(!caps.contains("tickets.edit"))
        #expect(!caps.contains("customers.create"))
        #expect(!caps.contains("customers.edit"))
        #expect(!caps.contains("invoices.create"))
        #expect(!caps.contains("sms.send"))
        #expect(!caps.contains("inventory.adjust"))
    }

    @Test("Read-Only preset has core read capabilities")
    func readOnlyHasCoreReadCaps() {
        let caps = RolePresetCatalog.readOnly.capabilities
        #expect(caps.contains("tickets.view.any"))
        #expect(caps.contains("customers.view"))
        #expect(caps.contains("inventory.view"))
        #expect(caps.contains("invoices.view"))
        #expect(caps.contains("sms.read"))
    }

    @Test("Read-Only is less permissive than Manager")
    func readOnlyLessPermissiveThanManager() {
        #expect(RolePresetCatalog.readOnly.capabilities.count
                < RolePresetCatalog.manager.capabilities.count)
    }

    // MARK: - Lookup

    @Test("preset(for:) returns correct preset")
    func lookupById() {
        let preset = RolePresetCatalog.preset(for: "catalog.cashier")
        #expect(preset?.name == "Cashier")
    }

    @Test("preset(for:) returns nil for unknown id")
    func lookupUnknownReturnsNil() {
        #expect(RolePresetCatalog.preset(for: "no.such.preset") == nil)
    }

    // MARK: - makeRole

    @Test("makeRole creates role with preset id and capabilities")
    func makeRoleFromPreset() {
        let preset = RolePresetCatalog.technician
        let role = preset.makeRole()
        #expect(role.preset == preset.id)
        #expect(role.capabilities == preset.capabilities)
        #expect(role.name == preset.name)
        #expect(!role.id.isEmpty)
    }

    @Test("makeRole generates unique ids on each call")
    func makeRoleUniqueIds() {
        let a = RolePresetCatalog.owner.makeRole()
        let b = RolePresetCatalog.owner.makeRole()
        #expect(a.id != b.id)
    }

    // MARK: - Hashable / Equatable

    @Test("identical RolePresetDescriptors are equal")
    func equalityHolds() {
        let p1 = RolePresetDescriptor(id: "x", name: "X", description: "desc",
                                      capabilities: ["a", "b"])
        let p2 = RolePresetDescriptor(id: "x", name: "X", description: "desc",
                                      capabilities: ["a", "b"])
        #expect(p1 == p2)
    }

    @Test("RolePresetDescriptors with different ids are not equal")
    func inequalityOnId() {
        let p1 = RolePresetDescriptor(id: "x", name: "X", description: "d", capabilities: ["a"])
        let p2 = RolePresetDescriptor(id: "y", name: "X", description: "d", capabilities: ["a"])
        #expect(p1 != p2)
    }
}
