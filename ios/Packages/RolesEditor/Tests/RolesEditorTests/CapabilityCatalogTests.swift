import Testing
@testable import RolesEditor

// MARK: - CapabilityCatalogTests

@Suite("CapabilityCatalog")
struct CapabilityCatalogTests {

    // MARK: Completeness

    @Test("all contains at least 60 capabilities")
    func allContainsMinimumCapabilities() {
        #expect(CapabilityCatalog.all.count >= 60)
    }

    @Test("all ids are unique")
    func allIdsAreUnique() {
        let ids = CapabilityCatalog.all.map(\.id)
        #expect(ids.count == Set(ids).count)
    }

    @Test("all capabilities have non-empty fields")
    func allFieldsNonEmpty() {
        for cap in CapabilityCatalog.all {
            #expect(!cap.id.isEmpty,          "id empty for \(cap.id)")
            #expect(!cap.domain.isEmpty,      "domain empty for \(cap.id)")
            #expect(!cap.label.isEmpty,       "label empty for \(cap.id)")
            #expect(!cap.description.isEmpty, "description empty for \(cap.id)")
        }
    }

    @Test("domains cover all expected groups")
    func expectedDomainsPresent() {
        let presentDomains = Set(CapabilityCatalog.all.map(\.domain))
        let expected: Set<String> = [
            "Tickets", "Customers", "Inventory", "Invoices", "SMS",
            "Reports", "Settings", "Hardware", "Audit", "Data",
            "Team", "Marketing", "Danger"
        ]
        #expect(expected.isSubset(of: presentDomains))
    }

    // MARK: Domain counts

    @Test("Tickets domain has 8 capabilities")
    func ticketsDomainCount() {
        #expect(CapabilityCatalog.tickets.count == 8)
    }

    @Test("Customers domain has 5 capabilities")
    func customersDomainCount() {
        #expect(CapabilityCatalog.customers.count == 5)
    }

    @Test("Inventory domain has 8 capabilities")
    func inventoryDomainCount() {
        #expect(CapabilityCatalog.inventory.count == 8)
    }

    @Test("Invoices domain has 7 capabilities")
    func invoicesDomainCount() {
        #expect(CapabilityCatalog.invoices.count == 7)
    }

    @Test("SMS domain has 4 capabilities")
    func smsDomainCount() {
        #expect(CapabilityCatalog.sms.count == 4)
    }

    @Test("Danger domain has 3 capabilities")
    func dangerDomainCount() {
        #expect(CapabilityCatalog.danger.count == 3)
    }

    // MARK: Specific capabilities

    @Test("critical capability IDs exist")
    func criticalCapabilityIds() {
        let ids = Set(CapabilityCatalog.all.map(\.id))
        let required = [
            "tickets.view.any", "tickets.delete",
            "customers.export",
            "invoices.payment.accept", "invoices.refund",
            "audit.view.all",
            "danger.tenant.delete", "danger.data.wipe",
            "team.view.payroll",
            "settings.edit.roles"
        ]
        for id in required {
            #expect(ids.contains(id), "Missing capability: \(id)")
        }
    }

    // MARK: Lookup helpers

    @Test("capability(for:) returns correct capability")
    func lookupByID() {
        let cap = CapabilityCatalog.capability(for: "tickets.view.any")
        #expect(cap?.label == "View any ticket")
        #expect(cap?.domain == "Tickets")
    }

    @Test("capability(for:) returns nil for unknown id")
    func lookupUnknownReturnsNil() {
        #expect(CapabilityCatalog.capability(for: "totally.made.up") == nil)
    }

    @Test("byDomain preserves all capabilities")
    func byDomainPreservesCount() {
        let grouped = CapabilityCatalog.byDomain
        let totalInGroups = grouped.reduce(0) { $0 + $1.capabilities.count }
        #expect(totalInGroups == CapabilityCatalog.all.count)
    }

    @Test("byDomain returns non-empty groups only")
    func byDomainNoEmptyGroups() {
        let grouped = CapabilityCatalog.byDomain
        for group in grouped {
            #expect(!group.capabilities.isEmpty, "Empty group for \(group.domain)")
        }
    }

    // MARK: Preset role capability correctness

    @Test("Owner preset contains all capabilities")
    func ownerPresetHasAllCaps() {
        let all = Set(CapabilityCatalog.all.map(\.id))
        #expect(RolePresets.owner.capabilities == all)
    }

    @Test("Manager preset excludes tenant.delete, billing, data.wipe")
    func managerPresetExcludesDangerCaps() {
        let caps = RolePresets.manager.capabilities
        #expect(!caps.contains("danger.tenant.delete"))
        #expect(!caps.contains("settings.billing"))
        #expect(!caps.contains("danger.data.wipe"))
        #expect(!caps.contains("data.wipe"))
    }

    @Test("Viewer preset is read-only")
    func viewerIsReadOnly() {
        let caps = RolePresets.viewer.capabilities
        // Should NOT have any create/edit/delete/send actions
        #expect(!caps.contains("tickets.create"))
        #expect(!caps.contains("customers.edit"))
        #expect(!caps.contains("invoices.create"))
        #expect(!caps.contains("sms.send"))
    }

    @Test("Training preset is the most restricted")
    func trainingIsMinimal() {
        #expect(RolePresets.training.capabilities.count < RolePresets.viewer.capabilities.count)
    }

    @Test("Cashier preset has POS payment but no refund")
    func cashierPresetHasPaymentNotRefund() {
        let caps = RolePresets.cashier.capabilities
        #expect(caps.contains("invoices.payment.accept"))
        #expect(!caps.contains("invoices.refund"))
    }

    @Test("Technician preset includes tickets.view.any")
    func technicianCanViewAnyTicket() {
        #expect(RolePresets.technician.capabilities.contains("tickets.view.any"))
    }

    @Test("all presets catalog has 10 entries")
    func presetCatalogCount() {
        #expect(RolePresets.all.count == 10)
    }

    @Test("all preset ids are unique")
    func presetIdsAreUnique() {
        let ids = RolePresets.all.map(\.id)
        #expect(ids.count == Set(ids).count)
    }

    @Test("cloneRole creates new id")
    func cloneCreatesNewId() {
        let original = RolePresets.owner.makeRole()
        let cloned = RolePresets.cloneRole(original, newName: "My Custom Role")
        #expect(cloned.id != original.id)
        #expect(cloned.name == "My Custom Role")
        #expect(cloned.preset == nil)
        #expect(cloned.capabilities == original.capabilities)
    }
}
