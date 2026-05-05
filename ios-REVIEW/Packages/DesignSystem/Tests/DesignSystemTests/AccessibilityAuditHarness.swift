import XCTest
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - §31.6 Accessibility Audit Harness
//
// Provides `XCUIApplication.performAccessibilityAudit()` style checks as unit-testable
// SwiftUI view introspection so the audit runs without a Simulator target.
//
// On iOS 17+ the system `performAccessibilityAudit()` can be used in XCUITest.
// This harness supplements that with pure-unit checks that run in XCTest (no simulator),
// exercising UIAccessibility properties through UIHostingController.
//
// Usage:
//
//   class BrandButtonA11yTests: XCTestCase {
//       func test_primaryButton_passesAudit() throws {
//           let view = BrandButton("Submit", action: {})
//           try AccessibilityAuditHarness.audit(view, testCase: self)
//       }
//   }

// MARK: - Audit issue

public struct AccessibilityAuditIssue: CustomStringConvertible {
    public enum Severity { case warning, error }
    public let severity: Severity
    public let description: String
}

// MARK: - Audit rules

/// A single, composable audit rule applied to a rendered view hierarchy.
public protocol AccessibilityAuditRule {
    var name: String { get }
    /// Inspect the rendered host view and return any issues found.
    @MainActor
    func check(_ hostView: UIView) -> [AccessibilityAuditIssue]
}

// MARK: - Built-in rules

/// Each interactive element must have a non-empty `accessibilityLabel`.
public struct MissingLabelRule: AccessibilityAuditRule {
    public let name = "MissingAccessibilityLabel"
    @MainActor
    public func check(_ hostView: UIView) -> [AccessibilityAuditIssue] {
        var issues: [AccessibilityAuditIssue] = []
        hostView.enumerateAccessibleElements { element in
            if element.isAccessibilityElement,
               (element.accessibilityLabel == nil || element.accessibilityLabel!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                issues.append(.init(
                    severity: .error,
                    description: "Element '\(type(of: element))' at \(element.accessibilityFrame) is accessible but has no label."
                ))
            }
        }
        return issues
    }
}

/// Buttons / interactive elements must meet WCAG 2.5.5 minimum tap target of 44×44 pt.
public struct TapTargetRule: AccessibilityAuditRule {
    public let name = "MinimumTapTarget"
    private let minimumSize: CGFloat

    public init(minimumSize: CGFloat = 44) {
        self.minimumSize = minimumSize
    }

    @MainActor
    public func check(_ hostView: UIView) -> [AccessibilityAuditIssue] {
        var issues: [AccessibilityAuditIssue] = []
        hostView.enumerateAccessibleElements { element in
            guard element.isAccessibilityElement else { return }
            let frame = element.accessibilityFrame
            if frame.width > 0, frame.height > 0 {
                if frame.width < minimumSize || frame.height < minimumSize {
                    issues.append(.init(
                        severity: .warning,
                        description: "Element '\(element.accessibilityLabel ?? "(no label)")' has tap target \(frame.size) — below \(minimumSize)×\(minimumSize) pt minimum."
                    ))
                }
            }
        }
        return issues
    }
}

/// Elements must not have duplicate accessibility identifiers in the same hierarchy.
public struct DuplicateIdentifierRule: AccessibilityAuditRule {
    public let name = "DuplicateAccessibilityIdentifier"
    @MainActor
    public func check(_ hostView: UIView) -> [AccessibilityAuditIssue] {
        var seen: [String: Int] = [:]
        hostView.enumerateAccessibleElements { element in
            if let id = element.accessibilityIdentifier, !id.isEmpty {
                seen[id, default: 0] += 1
            }
        }
        return seen
            .filter { $0.value > 1 }
            .map { id, count in
                AccessibilityAuditIssue(
                    severity: .warning,
                    description: "Accessibility identifier '\(id)' appears \(count) times in the hierarchy."
                )
            }
    }
}

/// VoiceOver traits: `.button` elements should have a non-nil label; `.image` elements should have a label or mark as decorative.
public struct TraitConsistencyRule: AccessibilityAuditRule {
    public let name = "TraitConsistency"
    @MainActor
    public func check(_ hostView: UIView) -> [AccessibilityAuditIssue] {
        var issues: [AccessibilityAuditIssue] = []
        hostView.enumerateAccessibleElements { element in
            guard element.isAccessibilityElement else { return }
            let traits = element.accessibilityTraits
            if traits.contains(.button) {
                if element.accessibilityLabel == nil || element.accessibilityLabel!.isEmpty {
                    issues.append(.init(
                        severity: .error,
                        description: "Button element has .button trait but no accessibility label."
                    ))
                }
            }
            if traits.contains(.image) {
                // Image should have a label or explicitly set isAccessibilityElement = false
                // (marking it decorative). We warn rather than error since purely decorative
                // images intentionally have no label.
                if element.accessibilityLabel == nil || element.accessibilityLabel!.isEmpty {
                    issues.append(.init(
                        severity: .warning,
                        description: "Image element has .image trait but no accessibility label — mark decorative (isAccessibilityElement=false) if intentional."
                    ))
                }
            }
        }
        return issues
    }
}

// MARK: - UIView traversal helper

private extension UIView {
    /// Walk the accessibility element tree depth-first.
    func enumerateAccessibleElements(_ visitor: (UIView) -> Void) {
        visitor(self)
        subviews.forEach { $0.enumerateAccessibleElements(visitor) }
    }
}

// MARK: - Harness

public enum AccessibilityAuditHarness {

    /// Default rules applied in `audit(_:testCase:)`.
    public static let defaultRules: [any AccessibilityAuditRule] = [
        MissingLabelRule(),
        TapTargetRule(),
        DuplicateIdentifierRule(),
        TraitConsistencyRule(),
    ]

    /// Render `view` at the given size, apply `rules`, and fail the test for any `.error` issues.
    /// Warnings are printed but do not fail.
    ///
    /// - Parameters:
    ///   - view: SwiftUI view to audit.
    ///   - rules: Audit rules to run (defaults to `AccessibilityAuditHarness.defaultRules`).
    ///   - size: Render size (default 390×844, iPhone 14 logical bounds).
    ///   - testCase: The calling test — used to record failures at the correct location.
    @MainActor
    public static func audit<V: View>(
        _ view: V,
        rules: [any AccessibilityAuditRule] = defaultRules,
        size: CGSize = CGSize(width: 390, height: 844),
        testCase: XCTestCase,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let controller = UIHostingController(rootView: view)
        controller.view.frame = CGRect(origin: .zero, size: size)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()

        var allIssues: [AccessibilityAuditIssue] = []
        for rule in rules {
            allIssues.append(contentsOf: rule.check(controller.view))
        }

        for issue in allIssues {
            switch issue.severity {
            case .error:
                XCTFail("[\(issue.severity)] \(issue.description)", file: file, line: line)
            case .warning:
                // Warnings surface in the test output without failing the build.
                print("⚠️  A11y audit warning: \(issue.description)")
            }
        }
    }

    /// Run a named subset of rules.
    @MainActor
    public static func audit<V: View>(
        _ view: V,
        rule: any AccessibilityAuditRule,
        size: CGSize = CGSize(width: 390, height: 844),
        testCase: XCTestCase,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        audit(view, rules: [rule], size: size, testCase: testCase, file: file, line: line)
    }
}

// MARK: - XCTestCase convenience

public extension XCTestCase {

    /// Convenience: audit a view against the default rule set.
    @MainActor
    func assertAccessible<V: View>(
        _ view: V,
        rules: [any AccessibilityAuditRule] = AccessibilityAuditHarness.defaultRules,
        size: CGSize = CGSize(width: 390, height: 844),
        file: StaticString = #file,
        line: UInt = #line
    ) {
        AccessibilityAuditHarness.audit(view, rules: rules, size: size,
                                         testCase: self, file: file, line: line)
    }
}

// MARK: - AccessibilityAuditHarnessTests

final class AccessibilityAuditHarnessTests: XCTestCase {

    // MARK: §31.6 harness smoke tests

    @MainActor
    func test_plainText_noErrors() {
        // A Text view with a literal string should pass the audit — it gets a
        // label from its content automatically.
        let view = Text("Hello, world!")
        AccessibilityAuditHarness.audit(view, testCase: self)
    }

    @MainActor
    func test_labelledButton_noMissingLabelError() {
        let view = Button("Submit") {}
        AccessibilityAuditHarness.audit(view, rules: [MissingLabelRule()], testCase: self)
    }

    @MainActor
    func test_missingLabelRule_detectsMissingLabel() {
        // UIView with `isAccessibilityElement = true` but no label — rule must fire.
        let hostView = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        let badElement = UIView(frame: CGRect(x: 10, y: 10, width: 50, height: 50))
        badElement.isAccessibilityElement = true
        badElement.accessibilityLabel = nil
        hostView.addSubview(badElement)

        let rule = MissingLabelRule()
        let issues = rule.check(hostView)
        XCTAssertFalse(issues.isEmpty, "MissingLabelRule must detect the unlabelled element")
        XCTAssertTrue(issues.allSatisfy { $0.severity == .error })
    }

    @MainActor
    func test_tapTargetRule_detectsSmallTarget() {
        let hostView = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        let smallButton = UIView(frame: CGRect(x: 0, y: 0, width: 20, height: 20))
        smallButton.isAccessibilityElement = true
        smallButton.accessibilityLabel = "Tiny"
        hostView.addSubview(smallButton)

        let rule = TapTargetRule(minimumSize: 44)
        let issues = rule.check(hostView)
        XCTAssertFalse(issues.isEmpty, "TapTargetRule must flag a 20×20 element")
    }

    @MainActor
    func test_tapTargetRule_passesSufficientTarget() {
        let hostView = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        let goodButton = UIView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        goodButton.isAccessibilityElement = true
        goodButton.accessibilityLabel = "OK"
        hostView.addSubview(goodButton)

        let rule = TapTargetRule(minimumSize: 44)
        let issues = rule.check(hostView)
        XCTAssertTrue(issues.isEmpty, "TapTargetRule must not flag a 44×44 element")
    }

    @MainActor
    func test_duplicateIdentifierRule_detectsDuplicates() {
        let hostView = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        for _ in 0..<2 {
            let v = UIView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
            v.accessibilityIdentifier = "submitButton"
            hostView.addSubview(v)
        }

        let rule = DuplicateIdentifierRule()
        let issues = rule.check(hostView)
        XCTAssertFalse(issues.isEmpty, "DuplicateIdentifierRule must flag repeated 'submitButton' id")
    }

    @MainActor
    func test_assertAccessible_xctestExtension_compiles() {
        // Validates the XCTestCase convenience extension exists and compiles.
        let view = Text("Test")
        assertAccessible(view, rules: [MissingLabelRule()])
    }
}
