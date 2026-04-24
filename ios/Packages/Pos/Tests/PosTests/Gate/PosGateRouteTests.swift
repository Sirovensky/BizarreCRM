/// PosGateRouteTests.swift
/// Agent B — Customer Gate (Frame 1)
///
/// Tests route equality and ensures the callback fires exactly once per action.

import XCTest
import Customers
import Networking
@testable import Pos

final class PosGateRouteTests: XCTestCase {

    // MARK: - Equatable

    func test_existing_equatable() {
        XCTAssertEqual(PosGateRoute.existing(1), PosGateRoute.existing(1))
        XCTAssertNotEqual(PosGateRoute.existing(1), PosGateRoute.existing(2))
    }

    func test_createNew_equatable() {
        XCTAssertEqual(PosGateRoute.createNew, PosGateRoute.createNew)
    }

    func test_walkIn_equatable() {
        XCTAssertEqual(PosGateRoute.walkIn, PosGateRoute.walkIn)
    }

    func test_openPickup_equatable() {
        XCTAssertEqual(PosGateRoute.openPickup(42), PosGateRoute.openPickup(42))
        XCTAssertNotEqual(PosGateRoute.openPickup(42), PosGateRoute.openPickup(99))
    }

    func test_differentCases_notEqual() {
        XCTAssertNotEqual(PosGateRoute.walkIn, PosGateRoute.createNew)
        XCTAssertNotEqual(PosGateRoute.walkIn, PosGateRoute.existing(1))
        XCTAssertNotEqual(PosGateRoute.createNew, PosGateRoute.openPickup(1))
    }

    // MARK: - Callback fires once

    @MainActor
    func test_callback_firesExactlyOnce_walkIn() {
        let vm = PosGateViewModel(
            customerRepo: PreviewCustomerRepository(),
            ticketsRepo: PreviewGateTicketsRepository()
        )
        var count = 0
        vm.onRouteSelected = { _ in count += 1 }
        vm.selectWalkIn()
        XCTAssertEqual(count, 1)
    }

    @MainActor
    func test_callback_firesExactlyOnce_createNew() {
        let vm = PosGateViewModel(
            customerRepo: PreviewCustomerRepository(),
            ticketsRepo: PreviewGateTicketsRepository()
        )
        var count = 0
        vm.onRouteSelected = { _ in count += 1 }
        vm.selectCreateNew()
        XCTAssertEqual(count, 1)
    }

    @MainActor
    func test_callback_firesExactlyOnce_existing() {
        let vm = PosGateViewModel(
            customerRepo: PreviewCustomerRepository(),
            ticketsRepo: PreviewGateTicketsRepository()
        )
        var count = 0
        vm.onRouteSelected = { _ in count += 1 }
        vm.selectExistingCustomer(id: 77)
        XCTAssertEqual(count, 1)
    }

    @MainActor
    func test_callback_firesExactlyOnce_openPickup() {
        let vm = PosGateViewModel(
            customerRepo: PreviewCustomerRepository(),
            ticketsRepo: PreviewGateTicketsRepository()
        )
        var count = 0
        vm.onRouteSelected = { _ in count += 1 }
        vm.openPickup(id: 55)
        XCTAssertEqual(count, 1)
    }

    // MARK: - Correct route value is delivered

    @MainActor
    func test_route_correct_existing() {
        let vm = PosGateViewModel(
            customerRepo: PreviewCustomerRepository(),
            ticketsRepo: PreviewGateTicketsRepository()
        )
        var delivered: PosGateRoute?
        vm.onRouteSelected = { delivered = $0 }
        vm.selectExistingCustomer(id: 123)
        XCTAssertEqual(delivered, .existing(123))
    }

    @MainActor
    func test_route_correct_openPickup() {
        let vm = PosGateViewModel(
            customerRepo: PreviewCustomerRepository(),
            ticketsRepo: PreviewGateTicketsRepository()
        )
        var delivered: PosGateRoute?
        vm.onRouteSelected = { delivered = $0 }
        vm.openPickup(id: 456)
        XCTAssertEqual(delivered, .openPickup(456))
    }
}
