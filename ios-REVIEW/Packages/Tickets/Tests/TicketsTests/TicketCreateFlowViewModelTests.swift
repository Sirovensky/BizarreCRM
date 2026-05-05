import XCTest
@testable import Tickets
import Networking

// §4.3 — TicketCreateFlowViewModel unit tests.
// Covers: step navigation, device management, pricing calculator,
// validation, submit happy-path + offline + server-error paths,
// and the DraftDevice checklist helpers.

@MainActor
final class TicketCreateFlowViewModelTests: XCTestCase {

    // MARK: - Step navigation

    func test_initialStep_isCustomer() {
        let vm = makeVM()
        XCTAssertEqual(vm.currentStep, .customer)
    }

    func test_canGoBack_falseAtCustomerStep() {
        let vm = makeVM()
        XCTAssertFalse(vm.canGoBack)
    }

    func test_next_withCustomer_advancesToDevices() {
        let vm = makeVM()
        vm.selectedCustomer = makeSampleCustomer()
        vm.next()
        XCTAssertEqual(vm.currentStep, .devices)
    }

    func test_next_withoutCustomer_staysAtCustomer() {
        let vm = makeVM()
        vm.next()
        XCTAssertEqual(vm.currentStep, .customer)
    }

    func test_back_fromDevices_returnsToCustomer() {
        let vm = makeVM()
        vm.selectedCustomer = makeSampleCustomer()
        vm.next()
        XCTAssertEqual(vm.currentStep, .devices)
        vm.back()
        XCTAssertEqual(vm.currentStep, .customer)
    }

    func test_canGoBack_trueAfterFirstStep() {
        let vm = makeVM()
        vm.selectedCustomer = makeSampleCustomer()
        vm.next()
        XCTAssertTrue(vm.canGoBack)
    }

    func test_allSteps_cycleForward() {
        let vm = makeVM()
        vm.selectedCustomer = makeSampleCustomer()
        vm.devices[0].deviceName = "iPhone"
        // customer → devices
        vm.next(); XCTAssertEqual(vm.currentStep, .devices)
        // devices → pricing (device has name)
        vm.next(); XCTAssertEqual(vm.currentStep, .pricing)
        // pricing → schedule
        vm.next(); XCTAssertEqual(vm.currentStep, .schedule)
        // schedule → review
        vm.next(); XCTAssertEqual(vm.currentStep, .review)
        // review: at end, next() is a no-op (review has no next)
        let before = vm.currentStep
        vm.next()
        XCTAssertEqual(vm.currentStep, before, "next() at review should not advance further")
    }

    // MARK: - Validation: devices step

    func test_stepValid_devicesStep_falseWhenDeviceNameEmpty() {
        let vm = makeVM()
        vm.selectedCustomer = makeSampleCustomer()
        vm.next() // → devices
        XCTAssertFalse(vm.stepValid, "empty device name should fail validation")
    }

    func test_stepValid_devicesStep_trueWhenDeviceNameSet() {
        let vm = makeVM()
        vm.selectedCustomer = makeSampleCustomer()
        vm.next()
        vm.updateDevice(at: 0) { $0.deviceName = "MacBook" }
        XCTAssertTrue(vm.stepValid)
    }

    // MARK: - Device management

    func test_addDevice_incrementsCount() {
        let vm = makeVM()
        XCTAssertEqual(vm.devices.count, 1)
        vm.addDevice()
        XCTAssertEqual(vm.devices.count, 2)
    }

    func test_removeDevice_decrementsCount() {
        let vm = makeVM()
        vm.addDevice()
        XCTAssertEqual(vm.devices.count, 2)
        vm.removeDevice(at: 1)
        XCTAssertEqual(vm.devices.count, 1)
    }

    func test_removeDevice_doesNotGoBelowOne() {
        let vm = makeVM()
        XCTAssertEqual(vm.devices.count, 1)
        vm.removeDevice(at: 0)
        XCTAssertEqual(vm.devices.count, 1, "last device should not be removable")
    }

    func test_updateDevice_mutatesCorrectDevice() {
        let vm = makeVM()
        vm.addDevice()
        vm.updateDevice(at: 1) { $0.deviceName = "iPad" }
        XCTAssertEqual(vm.devices[1].deviceName, "iPad")
        XCTAssertEqual(vm.devices[0].deviceName, "", "other device unchanged")
    }

    func test_updateDevice_outOfRange_noEffect() {
        let vm = makeVM()
        vm.updateDevice(at: 99) { $0.deviceName = "Ghost" }
        XCTAssertEqual(vm.devices.count, 1) // no crash + no change
    }

    // MARK: - Checklist helpers

    func test_toggleChecklistItem_flipsState() {
        let vm = makeVM()
        let itemId = vm.devices[0].checklist[0].id
        let initialState = vm.devices[0].checklist[0].checked
        vm.toggleChecklistItem(deviceIndex: 0, itemId: itemId)
        XCTAssertEqual(vm.devices[0].checklist[0].checked, !initialState)
    }

    func test_toggleChecklistItem_outOfRange_noEffect() {
        let vm = makeVM()
        vm.toggleChecklistItem(deviceIndex: 99, itemId: "fake-id")
        // No crash — devices unchanged
        XCTAssertEqual(vm.devices.count, 1)
    }

    func test_defaultChecklist_hasExpectedItems() {
        let items = DraftDevice.defaultChecklist()
        XCTAssertFalse(items.isEmpty)
        let labels = Set(items.map { $0.label })
        XCTAssertTrue(labels.contains("Screen cracked"))
        XCTAssertTrue(labels.contains("Water damage"))
    }

    // MARK: - Pricing calculator

    func test_subtotal_sumOfDevicePrices() {
        let vm = makeVM()
        vm.updateDevice(at: 0) { $0.price = 100 }
        vm.addDevice()
        vm.updateDevice(at: 1) { $0.price = 50 }
        XCTAssertEqual(vm.subtotal, 150, accuracy: 0.001)
    }

    func test_discountAmount_absolute() {
        let vm = makeVM()
        vm.updateDevice(at: 0) { $0.price = 200 }
        vm.discountText = "30"
        vm.discountMode = .absolute
        XCTAssertEqual(vm.discountAmount, 30, accuracy: 0.001)
        XCTAssertEqual(vm.grandTotal, 170, accuracy: 0.001)
    }

    func test_discountAmount_percent() {
        let vm = makeVM()
        vm.updateDevice(at: 0) { $0.price = 200 }
        vm.discountText = "10"
        vm.discountMode = .percent
        XCTAssertEqual(vm.discountAmount, 20, accuracy: 0.001)
        XCTAssertEqual(vm.grandTotal, 180, accuracy: 0.001)
    }

    func test_discountAmount_zeroWhenTextEmpty() {
        let vm = makeVM()
        vm.updateDevice(at: 0) { $0.price = 100 }
        vm.discountText = ""
        XCTAssertEqual(vm.discountAmount, 0, accuracy: 0.001)
    }

    func test_discountAmount_capsAtSubtotal() {
        let vm = makeVM()
        vm.updateDevice(at: 0) { $0.price = 100 }
        vm.discountText = "999"
        vm.discountMode = .absolute
        XCTAssertEqual(vm.discountAmount, 100, accuracy: 0.001)
        XCTAssertEqual(vm.grandTotal, 0, accuracy: 0.001)
    }

    func test_pricingStep_invalidDiscount_failsValidation() {
        let vm = makeVM()
        vm.selectedCustomer = makeSampleCustomer()
        vm.updateDevice(at: 0) { $0.deviceName = "X"; $0.price = 100 }
        // advance to pricing
        vm.next(); vm.next()
        XCTAssertEqual(vm.currentStep, .pricing)
        vm.discountText = "not-a-number"
        XCTAssertFalse(vm.stepValid)
    }

    func test_pricingStep_percentOver100_failsValidation() {
        let vm = makeVM()
        vm.selectedCustomer = makeSampleCustomer()
        vm.updateDevice(at: 0) { $0.deviceName = "X"; $0.price = 100 }
        vm.next(); vm.next()
        vm.discountMode = .percent
        vm.discountText = "110"
        XCTAssertFalse(vm.stepValid)
    }

    // MARK: - Submit happy path

    func test_submit_happyPath_setsCreatedTicketId() async {
        let api = Phase4StubAPIClient()
        await api.setCreateResult(.success(.init(id: 42)))
        let vm = TicketCreateFlowViewModel(api: api)
        vm.selectedCustomer = makeSampleCustomer()
        vm.updateDevice(at: 0) { $0.deviceName = "iPhone" }

        await vm.submit()

        XCTAssertEqual(vm.createdTicketId, 42)
        XCTAssertFalse(vm.queuedOffline)
        XCTAssertNil(vm.errorMessage)
    }

    func test_submit_withoutCustomer_setsError() async {
        let api = Phase4StubAPIClient()
        let vm = TicketCreateFlowViewModel(api: api)

        await vm.submit()

        XCTAssertNil(vm.createdTicketId)
        XCTAssertEqual(vm.errorMessage, "Pick a customer first.")
    }

    // MARK: - Submit offline path

    func test_submit_networkError_queuesOffline() async {
        let api = Phase4StubAPIClient()
        await api.setCreateResult(.failure(URLError(.notConnectedToInternet)))
        let vm = TicketCreateFlowViewModel(api: api)
        vm.selectedCustomer = makeSampleCustomer()
        vm.updateDevice(at: 0) { $0.deviceName = "Galaxy" }

        await vm.submit()

        XCTAssertEqual(vm.createdTicketId, PendingSyncTicketId)
        XCTAssertTrue(vm.queuedOffline)
        XCTAssertNil(vm.errorMessage)
    }

    // MARK: - Submit server error

    func test_submit_serverError_surfacesMessage() async {
        let api = Phase4StubAPIClient()
        await api.setCreateResult(.failure(APITransportError.httpStatus(403, message: "Forbidden")))
        let vm = TicketCreateFlowViewModel(api: api)
        vm.selectedCustomer = makeSampleCustomer()
        vm.updateDevice(at: 0) { $0.deviceName = "Pixel" }

        await vm.submit()

        XCTAssertNil(vm.createdTicketId)
        XCTAssertFalse(vm.queuedOffline)
        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: - Helpers

    private func makeVM() -> TicketCreateFlowViewModel {
        TicketCreateFlowViewModel(api: Phase4StubAPIClient())
    }
}

// MARK: - Phase4StubAPIClient convenience setters (actor-isolated)

private extension Phase4StubAPIClient {
    func setCreateResult(_ result: Result<CreatedResource, Error>) {
        createTicketResult = result
    }
}
