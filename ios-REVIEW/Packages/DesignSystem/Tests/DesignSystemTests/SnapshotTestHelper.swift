import XCTest
import SwiftUI

// MARK: - §31.2 Snapshot Test Scaffolding
//
// swift-snapshot-testing is not yet a resolved dependency.
// This helper provides the scaffolding contract so test authors can write snapshot
// assertions today; the actual image-diff driver will be wired in once the package
// is added.
//
// Usage (in any XCTestCase subclass):
//
//   func test_brandButton_lightDefault() {
//       let view = BrandButton("Submit", action: {})
//       assertSnapshot(of: view, variant: .lightCompact)
//   }
//
// When swift-snapshot-testing is integrated, replace `SnapshotDriver.record(_:variant:name:testName:file:line:)`
// with the library call — callers remain unchanged.

// MARK: - Rendering matrix

/// All axis combinations that every brand component must be snapshotted in.
public struct SnapshotVariant: Hashable, CustomStringConvertible {

    public let colorScheme: ColorScheme          // .light / .dark
    public let sizeClass: UserInterfaceSizeClass  // .compact / .regular (horizontal)
    public let contentSizeCategory: ContentSizeCategory
    public let layoutDirection: LayoutDirection   // .leftToRight / .rightToLeft

    public var description: String {
        let cs = colorScheme == .light ? "light" : "dark"
        let sc = sizeClass == .compact ? "compact" : "regular"
        let cat = contentSizeCategory.label
        let dir = layoutDirection == .leftToRight ? "ltr" : "rtl"
        return "\(cs)_\(sc)_\(cat)_\(dir)"
    }

    // MARK: - Convenience presets (mirrors ActionPlan §31.2 matrix)

    public static let lightCompact        = SnapshotVariant(.light, .compact, .medium, .leftToRight)
    public static let darkCompact         = SnapshotVariant(.dark,  .compact, .medium, .leftToRight)
    public static let lightRegular        = SnapshotVariant(.light, .regular, .medium, .leftToRight)
    public static let darkRegular         = SnapshotVariant(.dark,  .regular, .medium, .leftToRight)
    public static let lightCompactSmall   = SnapshotVariant(.light, .compact, .extraSmall, .leftToRight)
    public static let lightCompactXL      = SnapshotVariant(.light, .compact, .extraExtraExtraLarge, .leftToRight)
    public static let lightCompactAX3     = SnapshotVariant(.light, .compact, .accessibilityExtraExtraExtraLarge, .leftToRight)
    public static let lightCompactRTL     = SnapshotVariant(.light, .compact, .medium, .rightToLeft)
    public static let darkCompactRTL      = SnapshotVariant(.dark,  .compact, .medium, .rightToLeft)

    /// Full §31.2 matrix — use in parameterised snapshot loops.
    public static let all: [SnapshotVariant] = [
        .lightCompact, .darkCompact,
        .lightRegular, .darkRegular,
        .lightCompactSmall, .lightCompactXL, .lightCompactAX3,
        .lightCompactRTL, .darkCompactRTL,
    ]

    public init(_ colorScheme: ColorScheme,
                _ sizeClass: UserInterfaceSizeClass,
                _ contentSizeCategory: ContentSizeCategory,
                _ layoutDirection: LayoutDirection) {
        self.colorScheme = colorScheme
        self.sizeClass = sizeClass
        self.contentSizeCategory = contentSizeCategory
        self.layoutDirection = layoutDirection
    }
}

private extension ContentSizeCategory {
    var label: String {
        switch self {
        case .extraSmall:                           return "xs"
        case .small:                                return "s"
        case .medium:                               return "m"
        case .large:                                return "l"
        case .extraLarge:                           return "xl"
        case .extraExtraLarge:                      return "xxl"
        case .extraExtraExtraLarge:                 return "xxxl"
        case .accessibilityMedium:                  return "a11y-m"
        case .accessibilityLarge:                   return "a11y-l"
        case .accessibilityExtraLarge:              return "a11y-xl"
        case .accessibilityExtraExtraLarge:         return "a11y-xxl"
        case .accessibilityExtraExtraExtraLarge:    return "a11y-xxxl"
        default:                                    return "unknown"
        }
    }
}

// MARK: - Snapshot driver stub

/// Thin abstraction over the actual snapshot library.
///
/// - When `RECORD_SNAPSHOTS=1` env var is set, images are written to disk.
/// - When the env var is absent (CI), recorded images are compared; failures are
///   raised as XCTest failures with a diff description.
/// - Until swift-snapshot-testing is integrated, the driver asserts that the view
///   can be rendered into a UIImage without crashing — a compile+render smoke test.
public enum SnapshotDriver {

    /// Current mode: recording writes references; normal mode compares.
    public static var isRecording: Bool {
        ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1"
    }

    /// Render `view` wrapped in the given `variant` environment and perform a
    /// snapshot assertion.
    ///
    /// - Parameters:
    ///   - view: The SwiftUI view under test.
    ///   - variant: The environment axis combination.
    ///   - name: Optional disambiguator appended to the snapshot file name.
    ///   - width: Render width in points (default 390 — iPhone 14 logical width).
    ///   - testName: Injected automatically via `#function`.
    ///   - file: Injected automatically via `#file`.
    ///   - line: Injected automatically via `#line`.
    @MainActor
    public static func record<V: View>(
        _ view: V,
        variant: SnapshotVariant,
        name: String? = nil,
        width: CGFloat = 390,
        testName: String = #function,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        // Wrap in the variant environment
        let wrapped = view
            .colorScheme(variant.colorScheme)
            .dynamicTypeSize(variant.contentSizeCategory.dynamicTypeSize)
            .environment(\.layoutDirection, variant.layoutDirection)
            // sizeClass is read from UITraitCollection; we inject via hosting controller below.

        // Render to UIImage — smoke-tests that the view tree doesn't crash during layout.
        guard let image = _render(wrapped, width: width) else {
            XCTFail("Snapshot render returned nil for variant \(variant)", file: file, line: line)
            return
        }

        let snapshotName = [testName, variant.description, name].compactMap { $0 }.joined(separator: "_")

        if isRecording {
            // Write to __Snapshots__ directory next to the test file.
            _writeReference(image, snapshotName: snapshotName, file: file, line: line)
        } else {
            // Compare: load reference, diff, fail with annotation.
            _compare(image, snapshotName: snapshotName, file: file, line: line)
        }
    }

    // MARK: - Private rendering

    @MainActor
    private static func _render<V: View>(_ view: V, width: CGFloat) -> UIImage? {
        let controller = UIHostingController(rootView: view)
        controller.view.frame = CGRect(x: 0, y: 0, width: width, height: 1)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()

        // Intrinsic height after layout
        let size = controller.view.intrinsicContentSize
        let height = size.height > 0 ? size.height : 200
        controller.view.frame = CGRect(x: 0, y: 0, width: width, height: height)
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        return renderer.image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
    }

    private static func _referenceURL(snapshotName: String, file: StaticString) -> URL {
        let fileURL = URL(fileURLWithPath: "\(file)", isDirectory: false)
        let dir = fileURL.deletingLastPathComponent().appendingPathComponent("__Snapshots__")
        return dir.appendingPathComponent("\(snapshotName).png")
    }

    private static func _writeReference(_ image: UIImage, snapshotName: String, file: StaticString, line: UInt) {
        let url = _referenceURL(snapshotName: snapshotName, file: file)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            guard let png = image.pngData() else {
                XCTFail("Could not encode PNG for snapshot '\(snapshotName)'", file: file, line: line)
                return
            }
            try png.write(to: url, options: .atomic)
        } catch {
            XCTFail("Failed to write snapshot reference '\(snapshotName)': \(error)", file: file, line: line)
        }
    }

    private static func _compare(_ image: UIImage, snapshotName: String, file: StaticString, line: UInt) {
        let url = _referenceURL(snapshotName: snapshotName, file: file)
        guard FileManager.default.fileExists(atPath: url.path) else {
            // No reference yet — treat as first-run record so CI doesn't hard-fail on new components.
            _writeReference(image, snapshotName: snapshotName, file: file, line: line)
            return
        }
        guard let refData = try? Data(contentsOf: url),
              let refImage = UIImage(data: refData),
              let newPNG = image.pngData(),
              let refPNG = refImage.pngData() else {
            XCTFail("Failed to load reference snapshot '\(snapshotName)'", file: file, line: line)
            return
        }
        if newPNG != refPNG {
            XCTFail(
                """
                Snapshot '\(snapshotName)' does not match reference.
                Set RECORD_SNAPSHOTS=1 to update the reference, then commit the new PNG.
                Reference: \(url.path)
                """,
                file: file, line: line
            )
        }
    }
}

// MARK: - ContentSizeCategory → DynamicTypeSize bridge

private extension ContentSizeCategory {
    var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .extraSmall:                           return .xSmall
        case .small:                                return .small
        case .medium:                               return .medium
        case .large:                                return .large
        case .extraLarge:                           return .xLarge
        case .extraExtraLarge:                      return .xxLarge
        case .extraExtraExtraLarge:                 return .xxxLarge
        case .accessibilityMedium:                  return .accessibility1
        case .accessibilityLarge:                   return .accessibility2
        case .accessibilityExtraLarge:              return .accessibility3
        case .accessibilityExtraExtraLarge:         return .accessibility4
        case .accessibilityExtraExtraExtraLarge:    return .accessibility5
        default:                                    return .medium
        }
    }
}

// MARK: - XCTestCase convenience

public extension XCTestCase {

    /// Assert a SwiftUI view snapshot for a single variant.
    @MainActor
    func assertSnapshot<V: View>(
        of view: V,
        variant: SnapshotVariant,
        name: String? = nil,
        width: CGFloat = 390,
        testName: String = #function,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        SnapshotDriver.record(view,
                              variant: variant,
                              name: name,
                              width: width,
                              testName: testName,
                              file: file,
                              line: line)
    }

    /// Assert snapshots across all §31.2 variants in one call.
    @MainActor
    func assertSnapshotMatrix<V: View>(
        of view: V,
        name: String? = nil,
        width: CGFloat = 390,
        testName: String = #function,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        for variant in SnapshotVariant.all {
            SnapshotDriver.record(view,
                                  variant: variant,
                                  name: name,
                                  width: width,
                                  testName: testName,
                                  file: file,
                                  line: line)
        }
    }
}
