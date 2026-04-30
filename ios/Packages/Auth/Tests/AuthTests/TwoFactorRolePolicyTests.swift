import XCTest
@testable import Auth

final class TwoFactorRolePolicyTests: XCTestCase {

    func test_ownerRequires2FA() {
        XCTAssertTrue(TwoFactorRolePolicy.isRequired(for: "owner"))
    }

    func test_managerRequires2FA() {
        XCTAssertTrue(TwoFactorRolePolicy.isRequired(for: "manager"))
    }

    func test_adminRequires2FA() {
        XCTAssertTrue(TwoFactorRolePolicy.isRequired(for: "admin"))
    }

    func test_staffDoesNotRequire2FA() {
        XCTAssertFalse(TwoFactorRolePolicy.isRequired(for: "staff"))
    }

    func test_technicianDoesNotRequire2FA() {
        XCTAssertFalse(TwoFactorRolePolicy.isRequired(for: "technician"))
    }

    func test_cashierDoesNotRequire2FA() {
        XCTAssertFalse(TwoFactorRolePolicy.isRequired(for: "cashier"))
    }

    func test_roleCheckIsCaseInsensitive() {
        XCTAssertTrue(TwoFactorRolePolicy.isRequired(for: "OWNER"))
        XCTAssertTrue(TwoFactorRolePolicy.isRequired(for: "Manager"))
    }

    func test_tenantPolicyOptOut_disablesRequirement() {
        let policy = TenantSessionPolicy(require2FAForPrivilegedRoles: false)
        XCTAssertFalse(TwoFactorRolePolicy.isRequired(for: "owner", tenantPolicy: policy))
        XCTAssertFalse(TwoFactorRolePolicy.isRequired(for: "manager", tenantPolicy: policy))
    }

    func test_tenantPolicyOptIn_keepsRequirement() {
        let policy = TenantSessionPolicy(require2FAForPrivilegedRoles: true)
        XCTAssertTrue(TwoFactorRolePolicy.isRequired(for: "owner", tenantPolicy: policy))
        XCTAssertFalse(TwoFactorRolePolicy.isRequired(for: "staff", tenantPolicy: policy))
    }

    func test_tenantPolicyNil_appliesDefaults() {
        XCTAssertTrue(TwoFactorRolePolicy.isRequired(for: "owner", tenantPolicy: nil))
        XCTAssertFalse(TwoFactorRolePolicy.isRequired(for: "staff", tenantPolicy: nil))
    }
}
