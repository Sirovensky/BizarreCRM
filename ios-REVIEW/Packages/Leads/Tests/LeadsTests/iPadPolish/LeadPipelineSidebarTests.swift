import XCTest
@testable import Leads
@testable import Networking

// MARK: - LeadPipelineSidebarStatusTests

final class LeadPipelineSidebarStatusTests: XCTestCase {

    // MARK: - from(status:)

    func test_fromStatus_new() {
        XCTAssertEqual(LeadPipelineSidebarStatus.from(status: "new"), .new)
    }

    func test_fromStatus_contacted() {
        XCTAssertEqual(LeadPipelineSidebarStatus.from(status: "contacted"), .contacted)
    }

    func test_fromStatus_qualified() {
        XCTAssertEqual(LeadPipelineSidebarStatus.from(status: "qualified"), .qualified)
    }

    func test_fromStatus_converted() {
        XCTAssertEqual(LeadPipelineSidebarStatus.from(status: "converted"), .converted)
    }

    func test_fromStatus_lost() {
        XCTAssertEqual(LeadPipelineSidebarStatus.from(status: "lost"), .lost)
    }

    func test_fromStatus_caseInsensitive() {
        XCTAssertEqual(LeadPipelineSidebarStatus.from(status: "NEW"), .new)
        XCTAssertEqual(LeadPipelineSidebarStatus.from(status: "Contacted"), .contacted)
        XCTAssertEqual(LeadPipelineSidebarStatus.from(status: "QUALIFIED"), .qualified)
        XCTAssertEqual(LeadPipelineSidebarStatus.from(status: "CONVERTED"), .converted)
        XCTAssertEqual(LeadPipelineSidebarStatus.from(status: "LOST"), .lost)
    }

    func test_fromStatus_nil_fallsToNew() {
        XCTAssertEqual(LeadPipelineSidebarStatus.from(status: nil), .new)
    }

    func test_fromStatus_unknown_fallsToNew() {
        XCTAssertEqual(LeadPipelineSidebarStatus.from(status: "foobar"), .new)
        XCTAssertEqual(LeadPipelineSidebarStatus.from(status: ""), .new)
    }

    // MARK: - displayName

    func test_allStatuses_haveNonEmptyDisplayName() {
        for status in LeadPipelineSidebarStatus.allCases {
            XCTAssertFalse(status.displayName.isEmpty, "\(status.rawValue) has empty displayName")
        }
    }

    // MARK: - iconName

    func test_allStatuses_haveNonEmptyIconName() {
        for status in LeadPipelineSidebarStatus.allCases {
            XCTAssertFalse(status.iconName.isEmpty, "\(status.rawValue) has empty iconName")
        }
    }

    // MARK: - id

    func test_id_equalsRawValue() {
        for status in LeadPipelineSidebarStatus.allCases {
            XCTAssertEqual(status.id, status.rawValue)
        }
    }

    // MARK: - allCases

    func test_allCasesCount_isFive() {
        XCTAssertEqual(LeadPipelineSidebarStatus.allCases.count, 5)
    }
}

// MARK: - LeadPipelineSidebarViewModelTests

@MainActor
final class LeadPipelineSidebarViewModelTests: XCTestCase {

    // MARK: - Initial state

    func test_initialCounts_allZero() {
        let vm = LeadPipelineSidebarViewModel()
        for status in LeadPipelineSidebarStatus.allCases {
            XCTAssertEqual(vm.count(for: status), 0, "\(status.rawValue) should start at 0")
        }
    }

    func test_initialTotalCount_isZero() {
        let vm = LeadPipelineSidebarViewModel()
        XCTAssertEqual(vm.totalCount(), 0)
    }

    func test_initialSelectedStatus_isNil() {
        let vm = LeadPipelineSidebarViewModel()
        XCTAssertNil(vm.selectedStatus)
    }

    // MARK: - updateCounts

    func test_updateCounts_singleStatus() {
        let vm = LeadPipelineSidebarViewModel()
        let leads = [
            Lead(id: 1, status: "new"),
            Lead(id: 2, status: "new"),
            Lead(id: 3, status: "new"),
        ]
        vm.updateCounts(from: leads)
        XCTAssertEqual(vm.count(for: .new), 3)
        XCTAssertEqual(vm.count(for: .contacted), 0)
        XCTAssertEqual(vm.count(for: .lost), 0)
    }

    func test_updateCounts_mixedStatuses() {
        let vm = LeadPipelineSidebarViewModel()
        let leads = [
            Lead(id: 1, status: "new"),
            Lead(id: 2, status: "contacted"),
            Lead(id: 3, status: "qualified"),
            Lead(id: 4, status: "converted"),
            Lead(id: 5, status: "lost"),
            Lead(id: 6, status: "lost"),
        ]
        vm.updateCounts(from: leads)
        XCTAssertEqual(vm.count(for: .new), 1)
        XCTAssertEqual(vm.count(for: .contacted), 1)
        XCTAssertEqual(vm.count(for: .qualified), 1)
        XCTAssertEqual(vm.count(for: .converted), 1)
        XCTAssertEqual(vm.count(for: .lost), 2)
    }

    func test_updateCounts_nilStatus_bucketsToNew() {
        let vm = LeadPipelineSidebarViewModel()
        let leads = [Lead(id: 1, status: nil)]
        vm.updateCounts(from: leads)
        XCTAssertEqual(vm.count(for: .new), 1)
    }

    func test_updateCounts_unknownStatus_bucketsToNew() {
        let vm = LeadPipelineSidebarViewModel()
        let leads = [Lead(id: 1, status: "scheduled")]  // not a sidebar status
        vm.updateCounts(from: leads)
        XCTAssertEqual(vm.count(for: .new), 1)
    }

    func test_updateCounts_emptyList_allZero() {
        let vm = LeadPipelineSidebarViewModel()
        vm.updateCounts(from: [Lead(id: 1, status: "new"), Lead(id: 2, status: "lost")])
        vm.updateCounts(from: [])
        for status in LeadPipelineSidebarStatus.allCases {
            XCTAssertEqual(vm.count(for: status), 0)
        }
    }

    func test_updateCounts_isImmutable_doesNotMutatePreviousValue() {
        let vm = LeadPipelineSidebarViewModel()
        let firstBatch = [Lead(id: 1, status: "new"), Lead(id: 2, status: "new")]
        vm.updateCounts(from: firstBatch)
        let countAfterFirst = vm.count(for: .new)
        // Second update with different data.
        vm.updateCounts(from: [Lead(id: 3, status: "lost")])
        XCTAssertEqual(countAfterFirst, 2, "First count snapshot should be 2")
        XCTAssertEqual(vm.count(for: .new), 0, "New count should now be 0 after second update")
        XCTAssertEqual(vm.count(for: .lost), 1)
    }

    // MARK: - totalCount

    func test_totalCount_sumAllStatuses() {
        let vm = LeadPipelineSidebarViewModel()
        let leads = (1...7).map { Lead(id: Int64($0), status: ["new", "contacted", "qualified", "converted", "lost", "new", "lost"][$0 - 1]) }
        vm.updateCounts(from: leads)
        XCTAssertEqual(vm.totalCount(), 7)
    }

    func test_totalCount_emptyIsZero() {
        let vm = LeadPipelineSidebarViewModel()
        vm.updateCounts(from: [])
        XCTAssertEqual(vm.totalCount(), 0)
    }

    // MARK: - selectedStatus

    func test_selectedStatus_canBeSet() {
        let vm = LeadPipelineSidebarViewModel()
        vm.selectedStatus = .qualified
        XCTAssertEqual(vm.selectedStatus, .qualified)
    }

    func test_selectedStatus_canBeClearedToNil() {
        let vm = LeadPipelineSidebarViewModel()
        vm.selectedStatus = .lost
        vm.selectedStatus = nil
        XCTAssertNil(vm.selectedStatus)
    }
}
