import Testing
import Foundation
@testable import Marketing

@Suite("SegmentEditorViewModel")
@MainActor
struct SegmentEditorViewModelTests {

    @Test("initial state has empty rule group")
    func initialState() {
        let mock = MockAPIClient()
        let vm = SegmentEditorViewModel(api: mock)
        #expect(vm.rootGroup.op == "AND")
        #expect(vm.rootGroup.rules.isEmpty)
        #expect(vm.name.isEmpty)
        #expect(vm.liveCount == nil)
    }

    // MARK: - Rule tree mutations

    @Test("addLeaf appends a leaf rule")
    func addLeaf() {
        let mock = MockAPIClient()
        let vm = SegmentEditorViewModel(api: mock)
        vm.addLeaf()
        #expect(vm.rootGroup.rules.count == 1)
        if case .leaf(let f, let o, let v) = vm.rootGroup.rules[0] {
            #expect(!f.isEmpty)
            #expect(!o.isEmpty)
            #expect(v == "0")
        } else {
            Issue.record("Expected .leaf")
        }
    }

    @Test("addGroup appends a nested group rule")
    func addGroup() {
        let mock = MockAPIClient()
        let vm = SegmentEditorViewModel(api: mock)
        vm.addGroup()
        #expect(vm.rootGroup.rules.count == 1)
        if case .group(let g) = vm.rootGroup.rules[0] {
            #expect(g.rules.isEmpty)
        } else {
            Issue.record("Expected .group")
        }
    }

    @Test("removeRule removes at correct index")
    func removeRule() {
        let mock = MockAPIClient()
        let vm = SegmentEditorViewModel(api: mock)
        vm.addLeaf()
        vm.addLeaf()
        #expect(vm.rootGroup.rules.count == 2)
        vm.removeRule(at: 0)
        #expect(vm.rootGroup.rules.count == 1)
    }

    @Test("removeRule out-of-bounds is no-op")
    func removeRuleOutOfBounds() {
        let mock = MockAPIClient()
        let vm = SegmentEditorViewModel(api: mock)
        vm.addLeaf()
        vm.removeRule(at: 10) // out of bounds
        #expect(vm.rootGroup.rules.count == 1)
    }

    @Test("updateLeaf updates values at index, produces new struct (immutable)")
    func updateLeaf() {
        let mock = MockAPIClient()
        let vm = SegmentEditorViewModel(api: mock)
        vm.addLeaf()
        // Record old values before update
        let oldOp = vm.rootGroup.op
        vm.updateLeaf(at: 0, field: "ticket_count", op: ">", value: "5")
        // Verify the new value — struct is value type so identity check is not applicable
        #expect(vm.rootGroup.op == oldOp) // op unchanged
        if case .leaf(let f, let o, let v) = vm.rootGroup.rules[0] {
            #expect(f == "ticket_count")
            #expect(o == ">")
            #expect(v == "5")
        } else {
            Issue.record("Expected .leaf after update")
        }
    }

    @Test("setRootOp changes operator")
    func setRootOp() {
        let mock = MockAPIClient()
        let vm = SegmentEditorViewModel(api: mock)
        #expect(vm.rootGroup.op == "AND")
        vm.setRootOp("OR")
        #expect(vm.rootGroup.op == "OR")
    }

    @Test("applyPreset loads preset name and rules")
    func applyPreset() {
        let mock = MockAPIClient()
        let vm = SegmentEditorViewModel(api: mock)
        vm.applyPreset(SegmentPresets.vips)
        #expect(vm.name == "VIPs")
        #expect(!vm.rootGroup.rules.isEmpty)
    }

    @Test("applyPreset dormant has correct field")
    func applyPresetDormant() {
        let mock = MockAPIClient()
        let vm = SegmentEditorViewModel(api: mock)
        vm.applyPreset(SegmentPresets.dormant)
        #expect(vm.name == "Dormant")
        if case .leaf(let f, _, _) = vm.rootGroup.rules[0] {
            #expect(f == "last_visit_days_ago")
        } else {
            Issue.record("Expected leaf with last_visit_days_ago")
        }
    }

    // MARK: - Serialization

    @Test("serializedRule produces valid JSON with nested group")
    func serializedRule() throws {
        let mock = MockAPIClient()
        let vm = SegmentEditorViewModel(api: mock)
        vm.addLeaf()
        vm.addGroup()
        let data = try vm.serializedRule()
        #expect(data.count > 0)
        // Roundtrip
        let decoded = try JSONDecoder().decode(SegmentRuleGroup.self, from: data)
        #expect(decoded.op == vm.rootGroup.op)
        #expect(decoded.rules.count == vm.rootGroup.rules.count)
    }

    @Test("SegmentRule leaf roundtrips through JSON")
    func leafRoundtrip() throws {
        let leaf = SegmentRule.leaf(field: "lifetime_spend", op: ">", value: "500")
        let data = try JSONEncoder().encode(leaf)
        let decoded = try JSONDecoder().decode(SegmentRule.self, from: data)
        if case .leaf(let f, let o, let v) = decoded {
            #expect(f == "lifetime_spend")
            #expect(o == ">")
            #expect(v == "500")
        } else {
            Issue.record("Roundtrip failed for leaf")
        }
    }

    @Test("SegmentRule group roundtrips through JSON")
    func groupRoundtrip() throws {
        let group = SegmentRule.group(SegmentRuleGroup(op: "OR", rules: [
            .leaf(field: "ticket_count", op: "=", value: "1")
        ]))
        let data = try JSONEncoder().encode(group)
        let decoded = try JSONDecoder().decode(SegmentRule.self, from: data)
        if case .group(let g) = decoded {
            #expect(g.op == "OR")
            #expect(g.rules.count == 1)
        } else {
            Issue.record("Roundtrip failed for group")
        }
    }

    // MARK: - Save

    @Test("save calls createSegment and sets savedSegment")
    func saveSuccess() async {
        let mock = MockAPIClient()
        let vm = SegmentEditorViewModel(api: mock)
        vm.name = "My Segment"
        await vm.save()
        #expect(vm.savedSegment != nil)
        #expect(vm.errorMessage == nil)
        let calls = await mock.createSegmentCalled
        #expect(calls == 1)
    }

    @Test("save rejects empty name")
    func saveEmptyName() async {
        let mock = MockAPIClient()
        let vm = SegmentEditorViewModel(api: mock)
        vm.name = ""
        await vm.save()
        #expect(vm.errorMessage != nil)
        let calls = await mock.createSegmentCalled
        #expect(calls == 0)
    }
}
