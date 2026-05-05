#if DEBUG
import Foundation

// §31 Test Fixtures Helpers — RandomFixtureSeed
// A deterministic, seedable pseudo-random number generator based on a
// 64-bit Linear Congruential Generator (LCG).  Identical seed → identical
// sequence across platforms, making shuffled fixture lists reproducible.
//
// LCG constants from Knuth "TAOCP" vol. 2, Table 1 (modulus 2^64):
//   multiplier = 6364136223846793005
//   increment  = 1442695040888963407

/// A deterministic seeded PRNG for use in fixture generation.
///
/// Starting from the same `seed`, every call produces the same sequence of
/// values, so tests that shuffle or pick random elements are fully reproducible.
///
/// Usage:
/// ```swift
/// var rng = RandomFixtureSeed(seed: 42)
/// let index = rng.nextInt(in: 0..<items.count)
/// let shuffled = items.shuffled(using: &rng)
/// ```
public struct RandomFixtureSeed: RandomNumberGenerator {

    // MARK: — State

    private var state: UInt64

    // MARK: — Init

    /// - Parameter seed: Any 64-bit value. Use a constant in tests for reproducibility.
    public init(seed: UInt64 = 12_345) {
        self.state = seed
    }

    // MARK: — RandomNumberGenerator

    /// Advances the generator and returns the next 64-bit pseudo-random value.
    public mutating func next() -> UInt64 {
        // LCG step: state = (multiplier * state + increment) mod 2^64
        // The overflow is intentional (wrapping arithmetic ≡ mod 2^64).
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }

    // MARK: — Convenience helpers

    /// Returns a random integer in `range`, uniformly distributed.
    ///
    /// - Parameter range: A non-empty half-open range of `Int`.
    public mutating func nextInt(in range: Range<Int>) -> Int {
        precondition(!range.isEmpty, "RandomFixtureSeed.nextInt: range must be non-empty")
        let width = UInt64(bitPattern: Int64(range.upperBound - range.lowerBound))
        // Rejection-free bounded random using Lemire's "nearly divisionless" approach.
        let raw = next() % width
        return range.lowerBound + Int(raw)
    }

    /// Returns a random element from `collection`, or `nil` if the collection is empty.
    public mutating func randomElement<C: RandomAccessCollection>(from collection: C) -> C.Element? {
        guard !collection.isEmpty else { return nil }
        let index = nextInt(in: 0..<collection.count)
        return collection[collection.index(collection.startIndex, offsetBy: index)]
    }

    /// Returns a shuffled copy of `array`.  Same seed → same order every time.
    public mutating func shuffled<T>(_ array: [T]) -> [T] {
        var copy = array
        for i in stride(from: copy.count - 1, through: 1, by: -1) {
            let j = nextInt(in: 0...i)  // inclusive upper bound via half-open trick
            copy.swapAt(i, j)
        }
        return copy
    }

    // MARK: — Private helpers

    // Extends nextInt to support a closed range internally (used by shuffled).
    private mutating func nextInt(in range: ClosedRange<Int>) -> Int {
        nextInt(in: range.lowerBound..<(range.upperBound + 1))
    }
}
#endif
