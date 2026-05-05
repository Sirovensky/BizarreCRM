import XCTest
@testable import Reports

final class FinancialDashboardAccessControlTests: XCTestCase {

    func test_canAccess_ownerCapability_returnsTrue() {
        XCTAssertTrue(FinancialDashboardAccessControl.canAccess(
            roleCapabilities: ["financial_dashboard.view"]))
    }

    func test_canAccess_financeAdmin_returnsTrue() {
        XCTAssertTrue(FinancialDashboardAccessControl.canAccess(
            roleCapabilities: ["finance.admin"]))
    }

    func test_canAccess_reportsOwner_returnsTrue() {
        XCTAssertTrue(FinancialDashboardAccessControl.canAccess(
            roleCapabilities: ["reports.owner"]))
    }

    func test_canAccess_noRelevantCapability_returnsFalse() {
        XCTAssertFalse(FinancialDashboardAccessControl.canAccess(
            roleCapabilities: ["tickets.view", "inventory.read"]))
    }

    func test_canAccess_emptyCapabilities_returnsFalse() {
        XCTAssertFalse(FinancialDashboardAccessControl.canAccess(roleCapabilities: []))
    }

    func test_canAccessByRoleName_owner_returnsTrue() {
        XCTAssertTrue(FinancialDashboardAccessControl.canAccessByRoleName("owner"))
    }

    func test_canAccessByRoleName_caseInsensitive() {
        XCTAssertTrue(FinancialDashboardAccessControl.canAccessByRoleName("OWNER"))
        XCTAssertTrue(FinancialDashboardAccessControl.canAccessByRoleName("Owner"))
    }

    func test_canAccessByRoleName_employee_returnsFalse() {
        XCTAssertFalse(FinancialDashboardAccessControl.canAccessByRoleName("employee"))
    }

    func test_canAccessByRoleName_admin_returnsFalse() {
        XCTAssertFalse(FinancialDashboardAccessControl.canAccessByRoleName("admin"))
    }
}
