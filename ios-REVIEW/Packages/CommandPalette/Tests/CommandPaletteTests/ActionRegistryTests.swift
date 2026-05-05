import Testing
import Foundation
@testable import CommandPalette

// MARK: - Stub provider

private final class StubProvider: CommandActionProvider, @unchecked Sendable {
    let providerID: String
    private let _actions: [CommandAction]

    init(id: String, actions: [CommandAction]) {
        self.providerID = id
        self._actions = actions
    }

    func actions() -> [CommandAction] { _actions }
}

private func makeAction(id: String, title: String) -> CommandAction {
    CommandAction(id: id, title: title, icon: "star", keywords: [], handler: {})
}

// MARK: - Tests

@Suite("ActionRegistry")
struct ActionRegistryTests {

    @MainActor
    private func makeRegistry() -> ActionRegistry {
        // Each test gets a fresh registry via reset, not the shared singleton,
        // to keep tests isolated.
        let r = ActionRegistry.shared
        r._resetForTesting()
        return r
    }

    @Test("starts with no providers")
    @MainActor
    func startsEmpty() {
        let r = makeRegistry()
        #expect(r.providerCount == 0)
        #expect(r.allActions().isEmpty)
    }

    @Test("registering a provider adds its actions")
    @MainActor
    func registerAddsActions() {
        let r = makeRegistry()
        let provider = StubProvider(id: "tickets", actions: [
            makeAction(id: "new-ticket", title: "New Ticket")
        ])
        r.register(provider)
        #expect(r.allActions().count == 1)
        #expect(r.allActions().first?.id == "new-ticket")
    }

    @Test("registering two providers aggregates their actions")
    @MainActor
    func twoProvidersAggregateActions() {
        let r = makeRegistry()
        r.register(StubProvider(id: "tickets", actions: [
            makeAction(id: "new-ticket", title: "New Ticket")
        ]))
        r.register(StubProvider(id: "customers", actions: [
            makeAction(id: "new-customer", title: "New Customer"),
            makeAction(id: "find-customer", title: "Find Customer")
        ]))
        #expect(r.allActions().count == 3)
        #expect(r.providerCount == 2)
    }

    @Test("re-registering same providerID replaces the previous registration")
    @MainActor
    func reRegisterReplaces() {
        let r = makeRegistry()
        r.register(StubProvider(id: "tickets", actions: [makeAction(id: "a", title: "A")]))
        r.register(StubProvider(id: "tickets", actions: [makeAction(id: "b", title: "B")]))
        let ids = r.allActions().map { $0.id }
        #expect(ids == ["b"])
        #expect(r.providerCount == 1)
    }

    @Test("unregistering removes the provider's actions")
    @MainActor
    func unregisterRemovesActions() {
        let r = makeRegistry()
        r.register(StubProvider(id: "tickets", actions: [makeAction(id: "new-ticket", title: "New Ticket")]))
        r.unregister(providerID: "tickets")
        #expect(r.allActions().isEmpty)
        #expect(r.providerCount == 0)
    }

    @Test("unregistering unknown ID is a no-op")
    @MainActor
    func unregisterUnknownNoOp() {
        let r = makeRegistry()
        r.register(StubProvider(id: "tickets", actions: [makeAction(id: "a", title: "A")]))
        r.unregister(providerID: "does-not-exist")
        #expect(r.providerCount == 1)
    }

    @Test("actions(for:) returns correct provider's actions")
    @MainActor
    func actionsForProvider() {
        let r = makeRegistry()
        r.register(StubProvider(id: "tickets", actions: [makeAction(id: "new-ticket", title: "NT")]))
        r.register(StubProvider(id: "customers", actions: [makeAction(id: "new-customer", title: "NC")]))
        let ticketActions = r.actions(for: "tickets")
        #expect(ticketActions.map { $0.id } == ["new-ticket"])
    }

    @Test("actions(for:) returns empty for missing provider")
    @MainActor
    func actionsForMissingProvider() {
        let r = makeRegistry()
        #expect(r.actions(for: "nonexistent").isEmpty)
    }

    @Test("action registration order is preserved")
    @MainActor
    func registrationOrderPreserved() {
        let r = makeRegistry()
        r.register(StubProvider(id: "first",  actions: [makeAction(id: "a1", title: "A1")]))
        r.register(StubProvider(id: "second", actions: [makeAction(id: "b1", title: "B1")]))
        r.register(StubProvider(id: "third",  actions: [makeAction(id: "c1", title: "C1")]))
        let ids = r.allActions().map { $0.id }
        #expect(ids == ["a1", "b1", "c1"])
    }
}

// MARK: - CommandCatalog tests

@Suite("CommandCatalog")
struct CommandCatalogTests {

    @Test("default catalog produces 15 actions")
    func defaultCatalogCount() {
        let actions = CommandCatalog.defaultActions()
        #expect(actions.count == 15)
    }

    @Test("all action IDs are unique")
    func allIDsUnique() {
        let actions = CommandCatalog.defaultActions()
        let ids = actions.map { $0.id }
        #expect(Set(ids).count == ids.count)
    }

    @Test("all actions have non-empty titles")
    func allTitlesNonEmpty() {
        let actions = CommandCatalog.defaultActions()
        #expect(actions.allSatisfy { !$0.title.isEmpty })
    }

    @Test("all actions have non-empty SF Symbol names")
    func allIconsNonEmpty() {
        let actions = CommandCatalog.defaultActions()
        #expect(actions.allSatisfy { !$0.icon.isEmpty })
    }

    @Test("custom handlers are invoked")
    func customHandlersInvoked() {
        nonisolated(unsafe) var fired = false
        let actions = CommandCatalog.defaultActions(newTicket: { fired = true })
        let ticketAction = actions.first { $0.id == "new-ticket" }
        ticketAction?.handler()
        #expect(fired)
    }

    @Test("known action IDs are present in catalog")
    func knownIDsPresent() {
        let actions = CommandCatalog.defaultActions()
        let ids = Set(actions.map { $0.id })
        let expected: Set<String> = [
            "new-ticket", "new-customer", "find-customer-phone",
            "find-customer-name", "open-dashboard", "open-pos",
            "clock-in", "clock-out", "open-tickets", "open-inventory",
            "settings-tax", "settings-hours", "reports-revenue",
            "send-sms", "sign-out"
        ]
        #expect(ids == expected)
    }
}

// MARK: - EntityParser tests

@Suite("EntityParser")
struct EntityParserTests {

    @Test("nil for empty input")
    func emptyInput() {
        #expect(EntityParser.parse("") == nil)
        #expect(EntityParser.parse("   ") == nil)
    }

    @Test("ticket ID detected with # prefix")
    func ticketHashPrefix() {
        let result = EntityParser.parse("#1234")
        if case .ticket(let id) = result {
            #expect(id == "1234")
        } else {
            Issue.record("Expected .ticket, got \(String(describing: result))")
        }
    }

    @Test("ticket ID with alphanumeric and dash")
    func ticketAlphanumericDash() {
        let result = EntityParser.parse("#ABCD-1234")
        if case .ticket(let id) = result {
            #expect(id == "ABCD-1234")
        } else {
            Issue.record("Expected .ticket for '#ABCD-1234', got \(String(describing: result))")
        }
    }

    @Test("lone hash returns nil")
    func bareHashNil() {
        let result = EntityParser.parse("#")
        #expect(result == nil)
    }

    @Test("7-digit phone detected")
    func sevenDigitPhone() {
        let result = EntityParser.parse("5558675")
        if case .phone(let number) = result {
            #expect(number == "5558675")
        } else {
            Issue.record("Expected .phone, got \(String(describing: result))")
        }
    }

    @Test("10-digit formatted phone detected")
    func tenDigitFormattedPhone() {
        let result = EntityParser.parse("(555) 867-5309")
        if case .phone = result {
            // Pass — the exact digits are an implementation detail
        } else {
            Issue.record("Expected .phone for '(555) 867-5309', got \(String(describing: result))")
        }
    }

    @Test("short number below threshold does not match phone")
    func shortNumberNotPhone() {
        let result = EntityParser.parse("12345")
        // 5 digits is below the 7-digit threshold
        #expect(result == nil)
    }

    @Test("SKU uppercase alphanumeric with dash detected")
    func skuDetected() {
        let result = EntityParser.parse("SKU-1234")
        if case .sku(let value) = result {
            #expect(value == "SKU-1234")
        } else {
            Issue.record("Expected .sku for 'SKU-1234', got \(String(describing: result))")
        }
    }

    @Test("lowercase SKU-like string does not match SKU pattern")
    func lowercaseSkuNoMatch() {
        // Pattern requires uppercase — lowercase should not match
        let result = EntityParser.parse("sku-1234")
        // Either nil or phone — not .sku
        if case .sku = result {
            Issue.record("Unexpected .sku match for lowercase 'sku-1234'")
        }
    }

    @Test("plain text returns nil")
    func plainTextNil() {
        #expect(EntityParser.parse("ticket") == nil)
        #expect(EntityParser.parse("hello world") == nil)
    }
}
