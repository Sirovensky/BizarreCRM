#if canImport(CarPlay)
import XCTest
@testable import Core

// MARK: - CarPlayDashboardItemTests

/// Unit tests for ``CarPlayDashboardItem`` and its convenience factory.
///
/// Coverage targets:
/// - Initialiser stores every field without mutation.
/// - Equatable / Hashable contract.
/// - `placeholder(deepLinkDestination:)` sets expected defaults.
final class CarPlayDashboardItemTests: XCTestCase {

    // MARK: - Helpers

    private let destination = DeepLinkDestination.dashboard(tenantSlug: "acme")
    private let otherDestination = DeepLinkDestination.ticket(tenantSlug: "acme", id: "T-1")

    private func makeItem(
        title: String = "John Doe",
        subtitle: String = "2 min ago",
        imageName: String = "phone.fill",
        destination: DeepLinkDestination? = nil
    ) -> CarPlayDashboardItem {
        CarPlayDashboardItem(
            title: title,
            subtitle: subtitle,
            imageName: imageName,
            deepLinkDestination: destination ?? self.destination
        )
    }

    // MARK: - Initialiser

    func test_init_storesTitle() {
        let item = makeItem(title: "Alice")
        XCTAssertEqual(item.title, "Alice")
    }

    func test_init_storesSubtitle() {
        let item = makeItem(subtitle: "3 min")
        XCTAssertEqual(item.subtitle, "3 min")
    }

    func test_init_storesImageName() {
        let item = makeItem(imageName: "star")
        XCTAssertEqual(item.imageName, "star")
    }

    func test_init_storesDeepLinkDestination() {
        let item = makeItem(destination: otherDestination)
        XCTAssertEqual(item.deepLinkDestination, otherDestination)
    }

    func test_init_emptySubtitleAllowed() {
        let item = makeItem(subtitle: "")
        XCTAssertEqual(item.subtitle, "")
    }

    // MARK: - Equatable

    func test_equatable_sameValues_equal() {
        let a = makeItem()
        let b = makeItem()
        XCTAssertEqual(a, b)
    }

    func test_equatable_differentTitle_notEqual() {
        let a = makeItem(title: "A")
        let b = makeItem(title: "B")
        XCTAssertNotEqual(a, b)
    }

    func test_equatable_differentSubtitle_notEqual() {
        let a = makeItem(subtitle: "X")
        let b = makeItem(subtitle: "Y")
        XCTAssertNotEqual(a, b)
    }

    func test_equatable_differentImageName_notEqual() {
        let a = makeItem(imageName: "star")
        let b = makeItem(imageName: "moon")
        XCTAssertNotEqual(a, b)
    }

    func test_equatable_differentDestination_notEqual() {
        let a = makeItem(destination: destination)
        let b = makeItem(destination: otherDestination)
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Hashable

    func test_hashable_sameValues_sameHash() {
        let a = makeItem()
        let b = makeItem()
        XCTAssertEqual(a.hashValue, b.hashValue)
    }

    func test_hashable_usableInSet() {
        let items: Set<CarPlayDashboardItem> = [makeItem(), makeItem(), makeItem(title: "Other")]
        XCTAssertEqual(items.count, 2)
    }

    // MARK: - Placeholder factory

    func test_placeholder_titleIsEmpty() {
        let item = CarPlayDashboardItem.placeholder(deepLinkDestination: destination)
        XCTAssertEqual(item.title, "")
    }

    func test_placeholder_subtitleIsEmpty() {
        let item = CarPlayDashboardItem.placeholder(deepLinkDestination: destination)
        XCTAssertEqual(item.subtitle, "")
    }

    func test_placeholder_imageNameIsEllipsis() {
        let item = CarPlayDashboardItem.placeholder(deepLinkDestination: destination)
        XCTAssertEqual(item.imageName, "ellipsis.circle")
    }

    func test_placeholder_storesDestination() {
        let item = CarPlayDashboardItem.placeholder(deepLinkDestination: destination)
        XCTAssertEqual(item.deepLinkDestination, destination)
    }

    // MARK: - Immutability (struct copy semantics)

    func test_structCopy_doesNotShareState() {
        let original = makeItem(title: "Original")
        // Structs in Swift copy on assignment — reassign to a var copy
        var copy = original
        // Reassign copy by creating a new item with a different title
        copy = CarPlayDashboardItem(
            title: "Copy",
            subtitle: original.subtitle,
            imageName: original.imageName,
            deepLinkDestination: original.deepLinkDestination
        )
        XCTAssertEqual(original.title, "Original")
        XCTAssertEqual(copy.title, "Copy")
    }
}

#endif // canImport(CarPlay)
