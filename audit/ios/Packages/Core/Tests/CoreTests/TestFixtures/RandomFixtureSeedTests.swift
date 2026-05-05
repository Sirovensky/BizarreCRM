import XCTest
@testable import Core

// §31 Test Fixtures Helpers — RandomFixtureSeed Tests
// Covers: determinism, sequence independence from re-seeding, nextInt distribution,
// randomElement, shuffled reproducibility, shuffled produces all elements.

final class RandomFixtureSeedTests: XCTestCase {

    // MARK: — Determinism

    func test_sameSeed_producesIdenticalSequence() {
        var a = RandomFixtureSeed(seed: 42)
        var b = RandomFixtureSeed(seed: 42)
        let countToCheck = 20
        for _ in 0..<countToCheck {
            XCTAssertEqual(a.next(), b.next())
        }
    }

    func test_differentSeeds_produceDifferentFirstValues() {
        var a = RandomFixtureSeed(seed: 1)
        var b = RandomFixtureSeed(seed: 2)
        // Not guaranteed for ALL seeds, but for these two the LCG constants ensure divergence.
        XCTAssertNotEqual(a.next(), b.next())
    }

    func test_reseedingResetsSequence() {
        var rng = RandomFixtureSeed(seed: 77)
        let first  = rng.next()
        let second = rng.next()
        // Re-create with the same seed — must replay the same pair.
        var rng2 = RandomFixtureSeed(seed: 77)
        XCTAssertEqual(rng2.next(), first)
        XCTAssertEqual(rng2.next(), second)
    }

    // MARK: — nextInt(in:)

    func test_nextInt_alwaysWithinRange() {
        var rng = RandomFixtureSeed(seed: 99)
        let range = 0..<10
        for _ in 0..<1000 {
            let v = rng.nextInt(in: range)
            XCTAssertTrue(range.contains(v), "\(v) is outside \(range)")
        }
    }

    func test_nextInt_producesMultipleDistinctValues() {
        var rng = RandomFixtureSeed(seed: 1234)
        let range = 0..<100
        var seen = Set<Int>()
        for _ in 0..<200 {
            seen.insert(rng.nextInt(in: range))
        }
        // With 200 draws from 0..<100 we should see at least 50 distinct values.
        XCTAssertGreaterThan(seen.count, 50)
    }

    func test_nextInt_singleElementRange_alwaysReturnsThatElement() {
        var rng = RandomFixtureSeed(seed: 7)
        for _ in 0..<20 {
            XCTAssertEqual(rng.nextInt(in: 5..<6), 5)
        }
    }

    func test_nextInt_deterministic_givenSameSeed() {
        var a = RandomFixtureSeed(seed: 555)
        var b = RandomFixtureSeed(seed: 555)
        for _ in 0..<50 {
            XCTAssertEqual(a.nextInt(in: 0..<1000), b.nextInt(in: 0..<1000))
        }
    }

    // MARK: — randomElement

    func test_randomElement_emptyCollection_returnsNil() {
        var rng = RandomFixtureSeed(seed: 1)
        let result: Int? = rng.randomElement(from: [])
        XCTAssertNil(result)
    }

    func test_randomElement_singleElement_returnsThatElement() {
        var rng = RandomFixtureSeed(seed: 1)
        XCTAssertEqual(rng.randomElement(from: ["only"]), "only")
    }

    func test_randomElement_returnsElementFromCollection() {
        var rng = RandomFixtureSeed(seed: 42)
        let items = ["alpha", "beta", "gamma", "delta", "epsilon"]
        for _ in 0..<20 {
            let pick = rng.randomElement(from: items)
            XCTAssertNotNil(pick)
            XCTAssertTrue(items.contains(pick!))
        }
    }

    func test_randomElement_deterministic_givenSameSeed() {
        let items = [10, 20, 30, 40, 50]
        var a = RandomFixtureSeed(seed: 88)
        var b = RandomFixtureSeed(seed: 88)
        for _ in 0..<20 {
            XCTAssertEqual(a.randomElement(from: items), b.randomElement(from: items))
        }
    }

    // MARK: — shuffled

    func test_shuffled_sameSeed_producesSameOrder() {
        let array = Array(1...20)
        var a = RandomFixtureSeed(seed: 7)
        var b = RandomFixtureSeed(seed: 7)
        XCTAssertEqual(a.shuffled(array), b.shuffled(array))
    }

    func test_shuffled_differentSeeds_typicallyDifferentOrders() {
        let array = Array(1...10)
        var a = RandomFixtureSeed(seed: 1)
        var b = RandomFixtureSeed(seed: 999)
        // Not guaranteed but extremely likely with a length-10 array.
        XCTAssertNotEqual(a.shuffled(array), b.shuffled(array))
    }

    func test_shuffled_containsAllOriginalElements() {
        let array = ["x", "y", "z", "w", "v"]
        var rng = RandomFixtureSeed(seed: 3)
        let result = rng.shuffled(array)
        XCTAssertEqual(result.sorted(), array.sorted())
    }

    func test_shuffled_preservesCount() {
        let array = Array(0..<50)
        var rng = RandomFixtureSeed(seed: 12)
        XCTAssertEqual(rng.shuffled(array).count, array.count)
    }

    func test_shuffled_emptyArray_returnsEmpty() {
        var rng = RandomFixtureSeed(seed: 0)
        XCTAssertEqual(rng.shuffled([Int]()), [])
    }

    func test_shuffled_singleElement_returnsSameArray() {
        var rng = RandomFixtureSeed(seed: 0)
        XCTAssertEqual(rng.shuffled([42]), [42])
    }

    // MARK: — RandomNumberGenerator conformance

    func test_conformsToRandomNumberGenerator_canShuffleWithStdLib() {
        var rng = RandomFixtureSeed(seed: 42)
        let array = Array(1...10)
        // Uses the standard library's Array.shuffled(using:)
        let shuffled = array.shuffled(using: &rng)
        XCTAssertEqual(shuffled.count, array.count)
        XCTAssertEqual(shuffled.sorted(), array)
    }

    func test_conformsToRandomNumberGenerator_deterministicWithStdLib() {
        let array = Array(0..<15)
        var a = RandomFixtureSeed(seed: 111)
        var b = RandomFixtureSeed(seed: 111)
        XCTAssertEqual(array.shuffled(using: &a), array.shuffled(using: &b))
    }
}
