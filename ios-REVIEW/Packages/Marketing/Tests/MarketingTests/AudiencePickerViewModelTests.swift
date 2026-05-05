import Testing
import Foundation
@testable import Marketing

@Suite("AudiencePickerViewModel")
@MainActor
struct AudiencePickerViewModelTests {

    private func makeSegment(id: String = "s1", name: String = "VIPs", count: Int = 50) -> Segment {
        Segment(id: id, name: name, rule: SegmentRuleGroup(), cachedCount: count)
    }

    private func makeSmsGroup(id: Int = 1, name: String = "Newsletter", count: Int = 100, dynamic: Int = 0) -> SmsGroup {
        SmsGroup(id: id, name: name, description: nil, isDynamic: dynamic, memberCountCache: count)
    }

    // MARK: - Initial state

    @Test("initial state is empty")
    func initialState() {
        let mock = MockAPIClient()
        let vm = AudiencePickerViewModel(api: mock)
        #expect(vm.segments.isEmpty)
        #expect(vm.smsGroups.isEmpty)
        #expect(vm.isLoading == false)
        #expect(vm.errorMessage == nil)
        #expect(vm.searchText.isEmpty)
    }

    // MARK: - Load

    @Test("load populates segments and groups")
    func loadPopulates() async {
        let mock = MockAPIClient()
        mock.segmentListResult = .success(SegmentListResponse(segments: [
            makeSegment(id: "s1", name: "VIPs"),
            makeSegment(id: "s2", name: "Dormant")
        ]))
        await mock.setSmsGroupsResult(.success([
            makeSmsGroup(id: 10, name: "Newsletter")
        ]))
        let vm = AudiencePickerViewModel(api: mock)
        await vm.load()
        #expect(vm.segments.count == 2)
        #expect(vm.smsGroups.count == 1)
        #expect(vm.errorMessage == nil)
    }

    @Test("load sets errorMessage on segment failure")
    func loadSegmentError() async {
        let mock = MockAPIClient()
        mock.segmentListResult = .failure(URLError(.timedOut))
        let vm = AudiencePickerViewModel(api: mock)
        await vm.load()
        #expect(vm.errorMessage != nil)
        #expect(vm.segments.isEmpty)
    }

    @Test("load sets errorMessage on smsGroups failure")
    func loadSmsGroupsError() async {
        let mock = MockAPIClient()
        await mock.setSmsGroupsResult(.failure(URLError(.notConnectedToInternet)))
        let vm = AudiencePickerViewModel(api: mock)
        await vm.load()
        #expect(vm.errorMessage != nil)
    }

    @Test("isLoading is false after load completes")
    func isLoadingFalseAfterLoad() async {
        let mock = MockAPIClient()
        let vm = AudiencePickerViewModel(api: mock)
        await vm.load()
        #expect(vm.isLoading == false)
    }

    // MARK: - Search / filter

    @Test("filteredSegments returns all when searchText empty")
    func filteredSegmentsEmpty() async {
        let mock = MockAPIClient()
        mock.segmentListResult = .success(SegmentListResponse(segments: [
            makeSegment(id: "a", name: "Alpha"),
            makeSegment(id: "b", name: "Beta")
        ]))
        let vm = AudiencePickerViewModel(api: mock)
        await vm.load()
        vm.searchText = ""
        #expect(vm.filteredSegments.count == 2)
    }

    @Test("filteredSegments filters by name case-insensitively")
    func filteredSegmentsByName() async {
        let mock = MockAPIClient()
        mock.segmentListResult = .success(SegmentListResponse(segments: [
            makeSegment(id: "a", name: "Alpha"),
            makeSegment(id: "b", name: "Beta")
        ]))
        let vm = AudiencePickerViewModel(api: mock)
        await vm.load()
        vm.searchText = "alp"
        #expect(vm.filteredSegments.count == 1)
        #expect(vm.filteredSegments[0].name == "Alpha")
    }

    @Test("filteredSegments is empty when no match")
    func filteredSegmentsNoMatch() async {
        let mock = MockAPIClient()
        mock.segmentListResult = .success(SegmentListResponse(segments: [
            makeSegment(id: "a", name: "Alpha")
        ]))
        let vm = AudiencePickerViewModel(api: mock)
        await vm.load()
        vm.searchText = "xyz"
        #expect(vm.filteredSegments.isEmpty)
    }

    @Test("filteredGroups returns all when searchText empty")
    func filteredGroupsEmpty() async {
        let mock = MockAPIClient()
        await mock.setSmsGroupsResult(.success([
            makeSmsGroup(id: 1, name: "Newsletter"),
            makeSmsGroup(id: 2, name: "Promo")
        ]))
        let vm = AudiencePickerViewModel(api: mock)
        await vm.load()
        vm.searchText = ""
        #expect(vm.filteredGroups.count == 2)
    }

    @Test("filteredGroups filters by name case-insensitively")
    func filteredGroupsByName() async {
        let mock = MockAPIClient()
        await mock.setSmsGroupsResult(.success([
            makeSmsGroup(id: 1, name: "Newsletter"),
            makeSmsGroup(id: 2, name: "Promo")
        ]))
        let vm = AudiencePickerViewModel(api: mock)
        await vm.load()
        vm.searchText = "news"
        #expect(vm.filteredGroups.count == 1)
        #expect(vm.filteredGroups[0].name == "Newsletter")
    }

    @Test("search applies to both segments and groups simultaneously")
    func searchAppliesBoth() async {
        let mock = MockAPIClient()
        mock.segmentListResult = .success(SegmentListResponse(segments: [
            makeSegment(id: "s1", name: "Flash Sale")
        ]))
        await mock.setSmsGroupsResult(.success([
            makeSmsGroup(id: 1, name: "Flash Group")
        ]))
        let vm = AudiencePickerViewModel(api: mock)
        await vm.load()
        vm.searchText = "flash"
        #expect(vm.filteredSegments.count == 1)
        #expect(vm.filteredGroups.count == 1)
    }

    @Test("search clears restore all results")
    func searchClearRestores() async {
        let mock = MockAPIClient()
        mock.segmentListResult = .success(SegmentListResponse(segments: [
            makeSegment(id: "a", name: "Alpha"),
            makeSegment(id: "b", name: "Beta")
        ]))
        let vm = AudiencePickerViewModel(api: mock)
        await vm.load()
        vm.searchText = "alpha"
        #expect(vm.filteredSegments.count == 1)
        vm.searchText = ""
        #expect(vm.filteredSegments.count == 2)
    }
}
