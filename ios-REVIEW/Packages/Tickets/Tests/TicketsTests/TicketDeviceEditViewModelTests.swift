import XCTest
@testable import Tickets
import Networking

// §4.2 — TicketDeviceEditViewModel unit tests.
// Covers: validation, populate-from-device, add-mode, edit-mode,
// checklist toggle, server error, offline path.

@MainActor
final class TicketDeviceEditViewModelTests: XCTestCase {

    // MARK: - Validation

    func test_isValid_falseWhenDeviceNameEmpty() {
        let vm = makeAddVM()
        XCTAssertFalse(vm.isValid)
    }

    func test_isValid_trueWhenDeviceNameSet() {
        let vm = makeAddVM()
        vm.deviceName = "iPhone 14"
        XCTAssertTrue(vm.isValid)
    }

    func test_isValid_falseWhenOnlyWhitespace() {
        let vm = makeAddVM()
        vm.deviceName = "   "
        XCTAssertFalse(vm.isValid)
    }

    // MARK: - Price parsing

    func test_price_parsesDecimalString() {
        let vm = makeAddVM()
        vm.priceText = "129.99"
        XCTAssertEqual(vm.price, 129.99, accuracy: 0.001)
    }

    func test_price_parsesCommaAsDecimal() {
        let vm = makeAddVM()
        vm.priceText = "99,50"
        XCTAssertEqual(vm.price, 99.5, accuracy: 0.001)
    }

    func test_price_emptyStringGivesZero() {
        let vm = makeAddVM()
        vm.priceText = ""
        XCTAssertEqual(vm.price, 0, accuracy: 0.001)
    }

    // MARK: - Populate from device

    func test_populateFromDevice_fillsFields() {
        let vm = TicketDeviceEditViewModel(api: Phase4StubAPIClient(), mode: .edit(deviceId: 5))
        let device = makeDevice(
            id: 5,
            name: "Galaxy S24",
            imei: "490154203237518",
            serial: "R5CR9XXXXXX",
            price: 200
        )
        vm.populate(from: device)

        XCTAssertEqual(vm.deviceName, "Galaxy S24")
        XCTAssertEqual(vm.imei, "490154203237518")
        XCTAssertEqual(vm.serial, "R5CR9XXXXXX")
        XCTAssertEqual(vm.priceText, "200")
    }

    // MARK: - Add mode: happy path

    func test_save_addMode_happyPath_setsDoneFlag() async {
        let api = Phase4StubAPIClient()
        let vm = TicketDeviceEditViewModel(api: api, mode: .add(ticketId: 10))
        vm.deviceName = "iPhone 15 Pro"
        vm.priceText = "250"

        await vm.save()

        XCTAssertTrue(vm.didSave)
        XCTAssertNil(vm.errorMessage)
    }

    func test_save_addMode_callsCorrectEndpoint() async {
        let api = Phase4StubAPIClient()
        let vm = TicketDeviceEditViewModel(api: api, mode: .add(ticketId: 3))
        vm.deviceName = "iPad Pro"

        await vm.save()

        let path = await api.lastPostPath
        XCTAssertTrue(path.contains("/tickets/3/devices"), "Expected add-device endpoint, got \(path)")
    }

    // MARK: - Edit mode: happy path

    func test_save_editMode_happyPath_setsDoneFlag() async {
        let api = Phase4StubAPIClient()
        let vm = TicketDeviceEditViewModel(api: api, mode: .edit(deviceId: 7))
        vm.deviceName = "MacBook Air"
        vm.priceText = "300"

        await vm.save()

        XCTAssertTrue(vm.didSave)
        XCTAssertNil(vm.errorMessage)
    }

    func test_save_editMode_callsDevicesEndpoint() async {
        let api = Phase4StubAPIClient()
        let vm = TicketDeviceEditViewModel(api: api, mode: .edit(deviceId: 9))
        vm.deviceName = "Surface Pro"

        await vm.save()

        let path = await api.lastPutPath
        XCTAssertTrue(path.contains("/devices/9"), "Expected update-device endpoint, got \(path)")
    }

    // MARK: - Checklist operations

    func test_checklist_hasDefaultItems() {
        let vm = makeAddVM()
        XCTAssertFalse(vm.checklist.isEmpty)
    }

    func test_toggleChecklistItem_flipsState() {
        let vm = makeAddVM()
        let item = vm.checklist[0]
        let initial = item.checked
        vm.toggleChecklistItem(id: item.id)
        XCTAssertEqual(vm.checklist[0].checked, !initial)
    }

    func test_toggleChecklistItem_unknownId_noChange() {
        let vm = makeAddVM()
        let before = vm.checklist.map { $0.checked }
        vm.toggleChecklistItem(id: "no-such-id")
        let after = vm.checklist.map { $0.checked }
        XCTAssertEqual(before, after)
    }

    // MARK: - Validation guard prevents API call

    func test_save_emptyName_setsErrorAndNoAPICall() async {
        let api = Phase4StubAPIClient()
        let vm = TicketDeviceEditViewModel(api: api, mode: .add(ticketId: 1))

        await vm.save()

        XCTAssertFalse(vm.didSave)
        XCTAssertEqual(vm.errorMessage, "Device name is required.")
        let calls = await api.postCallCount
        XCTAssertEqual(calls, 0)
    }

    // MARK: - Server error

    func test_save_serverError_surfacesMessage() async {
        let api = Phase4StubAPIClient()
        await api.setAddDeviceFailure(APITransportError.httpStatus(422, message: "Invalid IMEI"))
        let vm = TicketDeviceEditViewModel(api: api, mode: .add(ticketId: 1))
        vm.deviceName = "Some device"
        vm.imei = "bad-imei"

        await vm.save()

        XCTAssertFalse(vm.didSave)
        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: - Helpers

    private func makeAddVM() -> TicketDeviceEditViewModel {
        TicketDeviceEditViewModel(api: Phase4StubAPIClient(), mode: .add(ticketId: 1))
    }

    private func makeDevice(
        id: Int64,
        name: String = "Device",
        imei: String? = nil,
        serial: String? = nil,
        price: Double? = nil
    ) -> TicketDetail.TicketDevice {
        let json = """
        {
          "id": \(id),
          "device_name": "\(name)",
          "imei": \(imei.map { "\"\($0)\"" } ?? "null"),
          "serial": \(serial.map { "\"\($0)\"" } ?? "null"),
          "price": \(price.map { String($0) } ?? "null"),
          "additional_notes": null
        }
        """
        let decoder = JSONDecoder()
        return try! decoder.decode(TicketDetail.TicketDevice.self, from: Data(json.utf8))
    }
}

// MARK: - Phase4StubAPIClient helpers

private extension Phase4StubAPIClient {
    func setAddDeviceFailure(_ error: Error) {
        addDeviceResult = .failure(error)
    }
}
