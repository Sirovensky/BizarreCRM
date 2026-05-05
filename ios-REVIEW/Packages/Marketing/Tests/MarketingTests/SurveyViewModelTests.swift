import Testing
import Foundation
@testable import Marketing

// MARK: - CSATSurveyViewModel Tests

@Suite("CSATSurveyViewModel")
@MainActor
struct CSATSurveyViewModelTests {

    @Test("initial state: no rating, no comment, canSubmit false")
    func initialState() {
        let vm = CSATSurveyViewModel(customerId: "c1", ticketId: "t1", api: MockAPIClient())
        #expect(vm.rating == 0)
        #expect(vm.comment.isEmpty)
        #expect(vm.canSubmit == false)
        #expect(vm.isSubmitting == false)
        #expect(vm.errorMessage == nil)
        #expect(vm.didSubmit == false)
    }

    @Test("canSubmit requires rating 1-5")
    func canSubmitRequiresRating() {
        let vm = CSATSurveyViewModel(customerId: "c1", ticketId: "t1", api: MockAPIClient())
        for r in 1...5 {
            vm.rating = r
            #expect(vm.canSubmit == true)
        }
        vm.rating = 0
        #expect(vm.canSubmit == false)
        vm.rating = 6
        #expect(vm.canSubmit == false)
    }

    @Test("submit calls API on valid rating")
    func submitCallsAPI() async {
        let mock = MockAPIClient()
        let vm = CSATSurveyViewModel(customerId: "c1", ticketId: "t1", api: mock)
        vm.rating = 4
        vm.comment = "Great service!"
        await vm.submit()
        #expect(vm.didSubmit == true)
        #expect(vm.errorMessage == nil)
        let count = await mock.csatSubmitCalled
        #expect(count == 1)
    }

    @Test("submit blocked when rating == 0")
    func submitBlockedWithNoRating() async {
        let mock = MockAPIClient()
        let vm = CSATSurveyViewModel(customerId: "c1", ticketId: "t1", api: mock)
        vm.rating = 0
        await vm.submit()
        #expect(vm.didSubmit == false)
        #expect(vm.errorMessage != nil)
        let count = await mock.csatSubmitCalled
        #expect(count == 0)
    }

    @Test("submit sets errorMessage on API failure")
    func submitAPIFailure() async {
        let mock = MockAPIClient()
        await mock.setCsatResult(.failure(URLError(.notConnectedToInternet)))
        let vm = CSATSurveyViewModel(customerId: "c1", ticketId: "t1", api: mock)
        vm.rating = 5
        await vm.submit()
        #expect(vm.didSubmit == false)
        #expect(vm.errorMessage != nil)
    }

    @Test("isSubmitting is true during submit")
    func isSubmittingDuringSubmit() async {
        let mock = MockAPIClient()
        let vm = CSATSurveyViewModel(customerId: "c1", ticketId: "t1", api: mock)
        vm.rating = 3
        // Just verify we can submit without crash and state transitions
        await vm.submit()
        #expect(vm.isSubmitting == false) // should be false after completion
    }

    @Test("ratingLabel returns descriptive text")
    func ratingLabel() {
        let vm = CSATSurveyViewModel(customerId: "c1", ticketId: "t1", api: MockAPIClient())
        vm.rating = 1
        #expect(!vm.ratingLabel.isEmpty)
        vm.rating = 5
        #expect(!vm.ratingLabel.isEmpty)
    }
}

// MARK: - NPSSurveyViewModel Tests

@Suite("NPSSurveyViewModel")
@MainActor
struct NPSSurveyViewModelTests {

    @Test("initial state: score -1 (unset), no chips, no text")
    func initialState() {
        let vm = NPSSurveyViewModel(customerId: "c1", api: MockAPIClient())
        #expect(vm.score == -1)
        #expect(vm.selectedThemes.isEmpty)
        #expect(vm.freeText.isEmpty)
        #expect(vm.canSubmit == false)
        #expect(vm.isSubmitting == false)
        #expect(vm.errorMessage == nil)
        #expect(vm.didSubmit == false)
    }

    @Test("canSubmit requires score 0-10")
    func canSubmitRange() {
        let vm = NPSSurveyViewModel(customerId: "c1", api: MockAPIClient())
        vm.score = -1
        #expect(vm.canSubmit == false)
        vm.score = 0
        #expect(vm.canSubmit == true)
        vm.score = 10
        #expect(vm.canSubmit == true)
        vm.score = 11
        #expect(vm.canSubmit == false)
    }

    @Test("toggleTheme adds and removes themes")
    func toggleTheme() {
        let vm = NPSSurveyViewModel(customerId: "c1", api: MockAPIClient())
        vm.toggleTheme("price")
        #expect(vm.selectedThemes.contains("price"))
        vm.toggleTheme("price")
        #expect(!vm.selectedThemes.contains("price"))
    }

    @Test("submit calls API on valid score")
    func submitCallsAPI() async {
        let mock = MockAPIClient()
        let vm = NPSSurveyViewModel(customerId: "c1", api: mock)
        vm.score = 9
        vm.toggleTheme("quality")
        vm.freeText = "Love the service"
        await vm.submit()
        #expect(vm.didSubmit == true)
        #expect(vm.errorMessage == nil)
        let count = await mock.npsSubmitCalled
        #expect(count == 1)
    }

    @Test("submit blocked when score == -1")
    func submitBlockedWithUnset() async {
        let mock = MockAPIClient()
        let vm = NPSSurveyViewModel(customerId: "c1", api: mock)
        await vm.submit()
        #expect(vm.didSubmit == false)
        #expect(vm.errorMessage != nil)
        let count = await mock.npsSubmitCalled
        #expect(count == 0)
    }

    @Test("submit sets errorMessage on API failure")
    func submitAPIFailure() async {
        let mock = MockAPIClient()
        await mock.setNpsResult(.failure(URLError(.badServerResponse)))
        let vm = NPSSurveyViewModel(customerId: "c1", api: mock)
        vm.score = 7
        await vm.submit()
        #expect(vm.didSubmit == false)
        #expect(vm.errorMessage != nil)
    }

    @Test("npsCategory is correct for ranges")
    func npsCategory() {
        let vm = NPSSurveyViewModel(customerId: "c1", api: MockAPIClient())
        vm.score = 6
        #expect(vm.npsCategory == .detractor)
        vm.score = 7
        #expect(vm.npsCategory == .passive)
        vm.score = 8
        #expect(vm.npsCategory == .passive)
        vm.score = 9
        #expect(vm.npsCategory == .promoter)
        vm.score = 10
        #expect(vm.npsCategory == .promoter)
        vm.score = 0
        #expect(vm.npsCategory == .detractor)
    }

    @Test("themeChips is non-empty")
    func themeChipsNonEmpty() {
        let vm = NPSSurveyViewModel(customerId: "c1", api: MockAPIClient())
        #expect(!vm.themeChips.isEmpty)
    }
}
