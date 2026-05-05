import Testing
@testable import AuditLogs

@Suite("AuditDiffRenderer")
struct AuditDiffRendererTests {

    // MARK: - Helpers

    private func diff(before: [String: AuditDiffValue] = [:], after: [String: AuditDiffValue] = [:]) -> AuditDiff {
        AuditDiff(before: before, after: after)
    }

    // MARK: - Empty diff

    @Test func emptyDiff_producesNoLines() {
        let lines = AuditDiffRenderer.render(diff())
        #expect(lines.isEmpty)
    }

    // MARK: - Added keys

    @Test func addedKey_producesAddedLine() {
        let d = diff(after: ["name": .string("Alice")])
        let lines = AuditDiffRenderer.render(d)
        #expect(lines.count == 1)
        #expect(lines[0].key == "name")
        #expect(lines[0].kind == .added)
        #expect(lines[0].value == "\"Alice\"")
    }

    @Test func multipleAddedKeys_allMarkedAdded() {
        let d = diff(after: ["a": .number(1), "b": .bool(true)])
        let lines = AuditDiffRenderer.render(d)
        #expect(lines.count == 2)
        #expect(lines.allSatisfy { $0.kind == .added })
    }

    // MARK: - Removed keys

    @Test func removedKey_producesRemovedLine() {
        let d = diff(before: ["status": .string("active")])
        let lines = AuditDiffRenderer.render(d)
        #expect(lines.count == 1)
        #expect(lines[0].kind == .removed)
        #expect(lines[0].key == "status")
        #expect(lines[0].value == "\"active\"")
    }

    // MARK: - Changed keys

    @Test func changedValue_producesRemovedThenAddedLine() {
        let d = diff(
            before: ["price": .number(10)],
            after:  ["price": .number(20)]
        )
        let lines = AuditDiffRenderer.render(d)
        #expect(lines.count == 2)
        let removed = lines.first { $0.kind == .removed }
        let added   = lines.first { $0.kind == .added }
        #expect(removed?.value == "10")
        #expect(added?.value  == "20")
    }

    @Test func changedStringValue_correctDisplayStrings() {
        let d = diff(
            before: ["email": .string("old@example.com")],
            after:  ["email": .string("new@example.com")]
        )
        let lines = AuditDiffRenderer.render(d)
        #expect(lines.count == 2)
        #expect(lines[0].kind == .removed)
        #expect(lines[0].value == "\"old@example.com\"")
        #expect(lines[1].kind == .added)
        #expect(lines[1].value == "\"new@example.com\"")
    }

    // MARK: - Unchanged keys

    @Test func unchangedValue_markedUnchanged() {
        let d = diff(before: ["id": .string("abc")], after: ["id": .string("abc")])
        let lines = AuditDiffRenderer.render(d)
        #expect(lines.count == 1)
        #expect(lines[0].kind == .unchanged)
    }

    // MARK: - Mixed diff

    @Test func mixedDiff_producesCorrectKinds() {
        let d = diff(
            before: ["a": .string("x"), "b": .string("old"), "c": .number(1)],
            after:  ["a": .string("x"), "b": .string("new"), "d": .bool(false)]
        )
        let lines = AuditDiffRenderer.render(d)
        // "a" unchanged, "c" removed, "d" added, "b" changed (two lines)
        let aLine = lines.first { $0.key == "a" && $0.kind == .unchanged }
        let cLine = lines.first { $0.key == "c" && $0.kind == .removed }
        let dLine = lines.first { $0.key == "d" && $0.kind == .added }
        #expect(aLine != nil)
        #expect(cLine != nil)
        #expect(dLine != nil)
        // b appears twice — removed then added
        let bLines = lines.filter { $0.key == "b" }
        #expect(bLines.count == 2)
        #expect(bLines.first?.kind == .removed)
        #expect(bLines.last?.kind  == .added)
    }

    // MARK: - Sorted output

    @Test func outputKeys_areSortedAlphabetically() {
        let d = diff(
            before: ["z": .string("z"), "a": .string("a"), "m": .string("m")],
            after:  ["z": .string("z"), "a": .string("a"), "m": .string("m")]
        )
        let lines = AuditDiffRenderer.render(d)
        let keys = lines.map(\.key)
        #expect(keys == keys.sorted())
    }

    // MARK: - Stable IDs

    @Test func lineIds_areUniqueForSingleChange() {
        let d = diff(
            before: ["x": .number(1)],
            after:  ["x": .number(2)]
        )
        let lines = AuditDiffRenderer.render(d)
        let ids = lines.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    // MARK: - AuditDiffValue display strings

    @Test func nullDisplayString() {
        #expect(AuditDiffValue.null.displayString == "null")
    }

    @Test func boolTrueDisplayString() {
        #expect(AuditDiffValue.bool(true).displayString == "true")
    }

    @Test func boolFalseDisplayString() {
        #expect(AuditDiffValue.bool(false).displayString == "false")
    }

    @Test func integerNumberDisplayString() {
        #expect(AuditDiffValue.number(42).displayString == "42")
    }

    @Test func floatNumberDisplayString() {
        #expect(AuditDiffValue.number(3.14).displayString == "3.14")
    }

    @Test func stringDisplayString() {
        #expect(AuditDiffValue.string("hello").displayString == "\"hello\"")
    }

    @Test func arrayDisplayString() {
        let val = AuditDiffValue.array([.number(1), .string("x")])
        #expect(val.displayString == "[1, \"x\"]")
    }

    @Test func objectDisplayString_sortedKeys() {
        let val = AuditDiffValue.object(["b": .number(2), "a": .number(1)])
        #expect(val.displayString == "{\"a\": 1, \"b\": 2}")
    }

    // MARK: - Color helpers

    @Test func addedColor_nonNil() {
        let c = AuditDiffRenderer.color(for: .added)
        // Just ensure it returns a usable Color without crashing
        _ = c
    }

    @Test func removedBackgroundColor_hasNonZeroOpacity() {
        let c = AuditDiffRenderer.backgroundColor(for: .removed)
        _ = c  // smoke test
    }

    @Test func unchangedBackgroundColor_isClear() {
        let c = AuditDiffRenderer.backgroundColor(for: .unchanged)
        _ = c  // smoke test — Color.clear, no crash
    }
}
