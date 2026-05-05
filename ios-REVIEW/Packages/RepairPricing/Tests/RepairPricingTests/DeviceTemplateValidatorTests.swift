import XCTest
@testable import RepairPricing

/// §43.5 — DeviceTemplateValidator unit tests.
final class DeviceTemplateValidatorTests: XCTestCase {

    // MARK: - Name validation

    func test_emptyName_producesNameEmptyError() {
        let errors = DeviceTemplateValidator.validate(name: "", family: "Apple", inlineServices: [])
        XCTAssertTrue(errors.contains(.nameEmpty))
    }

    func test_whitespaceName_producesNameEmptyError() {
        let errors = DeviceTemplateValidator.validate(name: "   ", family: "Apple", inlineServices: [])
        XCTAssertTrue(errors.contains(.nameEmpty))
    }

    func test_nameTooLong_producesNameTooLongError() {
        let longName = String(repeating: "x", count: 121)
        let errors = DeviceTemplateValidator.validate(name: longName, family: "Apple", inlineServices: [])
        XCTAssertTrue(errors.contains(.nameTooLong))
    }

    func test_exactlyMaxLengthName_isValid() {
        let name = String(repeating: "x", count: 120)
        let errors = DeviceTemplateValidator.validate(name: name, family: "Apple", inlineServices: [])
        XCTAssertFalse(errors.contains(.nameTooLong))
    }

    // MARK: - Family validation

    func test_emptyFamily_producesFamilyEmptyError() {
        let errors = DeviceTemplateValidator.validate(name: "iPhone 16", family: "", inlineServices: [])
        XCTAssertTrue(errors.contains(.familyEmpty))
    }

    func test_whitespaceFamily_producesFamilyEmptyError() {
        let errors = DeviceTemplateValidator.validate(name: "iPhone 16", family: "  ", inlineServices: [])
        XCTAssertTrue(errors.contains(.familyEmpty))
    }

    // MARK: - Service validation

    func test_serviceWithEmptyName_producesServiceNameError() {
        let svc = InlineService(name: "", rawPrice: "19.99", description: "")
        let errors = DeviceTemplateValidator.validate(name: "iPhone 16", family: "Apple", inlineServices: [svc])
        XCTAssertTrue(errors.contains(.serviceNameEmpty(index: 0)))
    }

    func test_serviceWithInvalidPrice_producesServicePriceError() {
        let svc = InlineService(name: "Screen", rawPrice: "abc", description: "")
        let errors = DeviceTemplateValidator.validate(name: "iPhone 16", family: "Apple", inlineServices: [svc])
        XCTAssertTrue(errors.contains(.servicePriceInvalid(index: 0)))
    }

    func test_serviceWithZeroPrice_producesServicePriceError() {
        let svc = InlineService(name: "Screen", rawPrice: "0", description: "")
        let errors = DeviceTemplateValidator.validate(name: "iPhone 16", family: "Apple", inlineServices: [svc])
        XCTAssertTrue(errors.contains(.servicePriceInvalid(index: 0)))
    }

    func test_validService_producesNoErrors() {
        let svc = InlineService(name: "Screen Replacement", rawPrice: "199.99", description: "")
        let errors = DeviceTemplateValidator.validate(name: "iPhone 16", family: "Apple", inlineServices: [svc])
        XCTAssertTrue(errors.isEmpty)
    }

    func test_multipleServices_errorsAtCorrectIndices() {
        let good = InlineService(name: "Battery", rawPrice: "59.00")
        let bad  = InlineService(name: "",        rawPrice: "-1")
        let errors = DeviceTemplateValidator.validate(name: "iPhone 16", family: "Apple", inlineServices: [good, bad])
        XCTAssertTrue(errors.contains(.serviceNameEmpty(index: 1)))
        XCTAssertTrue(errors.contains(.servicePriceInvalid(index: 1)))
        XCTAssertFalse(errors.contains(.serviceNameEmpty(index: 0)))
    }

    // MARK: - Valid form → no errors

    func test_validFormWithServices_producesNoErrors() {
        let svcs = [
            InlineService(name: "Screen", rawPrice: "199.00"),
            InlineService(name: "Battery", rawPrice: "59.00")
        ]
        let errors = DeviceTemplateValidator.validate(name: "iPhone 16", family: "Apple", inlineServices: svcs)
        XCTAssertTrue(errors.isEmpty)
    }

    func test_validFormNoServices_producesNoErrors() {
        let errors = DeviceTemplateValidator.validate(name: "iPhone 16", family: "Apple", inlineServices: [])
        XCTAssertTrue(errors.isEmpty)
    }

    // MARK: - Multiple errors accumulate

    func test_multipleFieldErrors_accumulateCorrectly() {
        let errors = DeviceTemplateValidator.validate(name: "", family: "", inlineServices: [])
        XCTAssertTrue(errors.contains(.nameEmpty))
        XCTAssertTrue(errors.contains(.familyEmpty))
        XCTAssertEqual(errors.count, 2)
    }

    // MARK: - Error descriptions

    func test_allErrorDescriptions_areNotEmpty() {
        let cases: [DeviceTemplateValidator.ValidationError] = [
            .nameEmpty, .nameTooLong, .familyEmpty,
            .serviceNameEmpty(index: 0), .servicePriceInvalid(index: 0)
        ]
        for err in cases {
            XCTAssertFalse(err.errorDescription?.isEmpty ?? true, "Empty description for \(err)")
        }
    }
}
