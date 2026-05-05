import XCTest
@testable import Hardware

final class BonjourPrinterBrowserTests: XCTestCase {

    // MARK: - MockBonjourPrinterBrowser

    func test_mockBrowser_emitsStubbed() async {
        let stub = DiscoveredPrinter(id: "test::Star TSP100IV", name: "Star TSP100IV", serviceType: "_ipp._tcp")
        let browser = MockBonjourPrinterBrowser(stubbedPrinters: [stub])

        let stream = await browser.discoveryStream()
        var iterator = stream.makeAsyncIterator()
        let result = await iterator.next()
        XCTAssertEqual(result?.count, 1)
        XCTAssertEqual(result?.first?.name, "Star TSP100IV")
    }

    func test_mockBrowser_refresh_incrementsCount() async {
        let browser = MockBonjourPrinterBrowser()
        await browser.refresh()
        await browser.refresh()
        let count = await browser.refreshCallCount
        XCTAssertEqual(count, 2)
    }

    func test_mockBrowser_stop_incrementsCount() async {
        let browser = MockBonjourPrinterBrowser()
        await browser.stop()
        let count = await browser.stopCallCount
        XCTAssertEqual(count, 1)
    }

    // MARK: - DiscoveredPrinter properties

    func test_discoveredPrinter_ippServiceLabel() {
        let printer = DiscoveredPrinter(id: "id", name: "Test", serviceType: "_ipp._tcp")
        XCTAssertEqual(printer.serviceLabel, "IPP / AirPrint")
    }

    func test_discoveredPrinter_lpdServiceLabel() {
        let printer = DiscoveredPrinter(id: "id", name: "Test", serviceType: "_printer._tcp")
        XCTAssertEqual(printer.serviceLabel, "LPD Printer")
    }

    func test_discoveredPrinter_bizarreServiceLabel() {
        let printer = DiscoveredPrinter(id: "id", name: "Test", serviceType: "_bizarre._tcp")
        XCTAssertEqual(printer.serviceLabel, "BizarreCRM")
    }

    func test_discoveredPrinter_ippSystemImage() {
        let printer = DiscoveredPrinter(id: "id", name: "Test", serviceType: "_ipp._tcp")
        XCTAssertEqual(printer.systemImageName, "printer")
    }

    func test_discoveredPrinter_bizarreSystemImage() {
        let printer = DiscoveredPrinter(id: "id", name: "Test", serviceType: "_bizarre._tcp")
        XCTAssertEqual(printer.systemImageName, "bolt.horizontal")
    }

    // MARK: - Hashable + Equatable

    func test_discoveredPrinter_equatable() {
        let a = DiscoveredPrinter(id: "x", name: "P1", serviceType: "_ipp._tcp")
        let b = DiscoveredPrinter(id: "x", name: "P1", serviceType: "_ipp._tcp")
        XCTAssertEqual(a, b)
    }

    func test_discoveredPrinter_notEqual() {
        let a = DiscoveredPrinter(id: "x", name: "P1", serviceType: "_ipp._tcp")
        let b = DiscoveredPrinter(id: "y", name: "P2", serviceType: "_ipp._tcp")
        XCTAssertNotEqual(a, b)
    }
}
