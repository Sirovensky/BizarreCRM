import XCTest
@testable import Camera

final class DocumentAutoClassifierTests: XCTestCase {

    let classifier = DocumentAutoClassifier()

    func test_classifyReceipt() {
        let text = """
        Thank you for your purchase!
        Total paid: $45.00
        Visa ****1234 Approved
        Transaction ID: TXN001
        Cashier: Alex
        """
        let (tag, confidence) = classifier.classify(text: text)
        XCTAssertEqual(tag, .receipt)
        XCTAssertGreaterThan(confidence, 0.25)
    }

    func test_classifyInvoice() {
        let text = """
        INVOICE #INV-2024-001
        Bill To: Acme Corp
        Ship To: 123 Main St
        Payment Terms: Net 30
        Due Date: 2024-05-01
        Qty  Unit Price  Total
        2    $50.00      $100.00
        """
        let (tag, confidence) = classifier.classify(text: text)
        XCTAssertEqual(tag, .invoice)
        XCTAssertGreaterThan(confidence, 0.25)
    }

    func test_classifyWarranty() {
        let text = """
        LIMITED WARRANTY
        This product is covered by a one-year warranty against defects.
        Serial Number: SN123456
        Model Number: MN789
        Proof of purchase required for warranty claims.
        This warranty excludes damage from misuse.
        """
        let (tag, confidence) = classifier.classify(text: text)
        XCTAssertEqual(tag, .warranty)
        XCTAssertGreaterThan(confidence, 0.25)
    }

    func test_classifyLicense() {
        let text = """
        DRIVER LICENSE
        Name: John Doe
        Date of Birth: 1990-01-01
        DL# D1234567
        Class: C
        Expiration: 2028-01-01
        """
        let (tag, confidence) = classifier.classify(text: text)
        XCTAssertEqual(tag, .license)
        XCTAssertGreaterThan(confidence, 0.25)
    }

    func test_classifyOther_emptyText() {
        let (tag, _) = classifier.classify(text: "")
        XCTAssertEqual(tag, .other)
    }

    func test_classifyOther_unknownText() {
        let (tag, _) = classifier.classify(text: "Lorem ipsum dolor sit amet consectetur")
        XCTAssertEqual(tag, .other)
    }

    func test_caseInsensitive() {
        // Uppercase keywords should still match
        let text = "INVOICE NUMBER: 001 BILL TO: Customer PAYMENT TERMS: NET 30"
        let (tag, _) = classifier.classify(text: text)
        XCTAssertEqual(tag, .invoice)
    }

    func test_minimumConfidence_customThreshold() {
        // With a very high threshold, even a well-matching doc yields .other
        let strictClassifier = DocumentAutoClassifier(minimumConfidence: 0.99)
        let text = "INVOICE #001 Bill To: Acme Corp Payment Terms: Net 30"
        let (tag, _) = strictClassifier.classify(text: text)
        XCTAssertEqual(tag, .other)
    }
}
