import XCTest
@testable import Networking

// MARK: - RetryExecutorTests

// Swift 6 note: RetryExecutor.execute() takes a @Sendable closure, so local
// `var callCount` variables cannot be captured mutably. We use an actor-isolated
// counter per test to satisfy the compiler without changing the executor API.
private actor Counter {
    private(set) var value: Int = 0
    func increment() { value += 1 }
}

final class RetryExecutorTests: XCTestCase {

    // MARK: Mulberry32 PRNG

    func testMulberry32ProducesValueInRange() {
        var prng = Mulberry32(seed: 42)
        for _ in 0..<100 {
            let v = prng.nextDouble()
            XCTAssertGreaterThanOrEqual(v, 0)
            XCTAssertLessThan(v, 1)
        }
    }

    func testMulberry32IsDeterministicWithSameSeed() {
        var a = Mulberry32(seed: 12345)
        var b = Mulberry32(seed: 12345)
        for _ in 0..<20 {
            XCTAssertEqual(a.nextDouble(), b.nextDouble())
        }
    }

    func testMulberry32DifferentSeedsProduceDifferentSequences() {
        var a = Mulberry32(seed: 1)
        var b = Mulberry32(seed: 2)
        // At least one value should differ
        var differs = false
        for _ in 0..<10 {
            if a.nextDouble() != b.nextDouble() { differs = true; break }
        }
        XCTAssertTrue(differs)
    }

    // MARK: computedDelay — jitter disabled

    func testComputedDelayNoJitterMatchesExponential() {
        let policy = RetryPolicy(maxAttempts: 5, baseDelay: 1, maxDelay: 60, jitter: false)
        let executor = RetryExecutor(policy: policy)
        var prng = Mulberry32(seed: 0)
        XCTAssertEqual(executor.computedDelay(forAttempt: 0, prng: &prng), 1, accuracy: 0.0001)
        XCTAssertEqual(executor.computedDelay(forAttempt: 1, prng: &prng), 2, accuracy: 0.0001)
        XCTAssertEqual(executor.computedDelay(forAttempt: 2, prng: &prng), 4, accuracy: 0.0001)
    }

    func testComputedDelayNoJitterCappedByMaxDelay() {
        let policy = RetryPolicy(maxAttempts: 5, baseDelay: 1, maxDelay: 3, jitter: false)
        let executor = RetryExecutor(policy: policy)
        var prng = Mulberry32(seed: 0)
        // attempt 2: 1*4=4 capped to 3
        XCTAssertEqual(executor.computedDelay(forAttempt: 2, prng: &prng), 3, accuracy: 0.0001)
    }

    // MARK: computedDelay — jitter enabled

    func testComputedDelayWithJitterIsWithinRange() {
        let policy = RetryPolicy(maxAttempts: 5, baseDelay: 1, maxDelay: 60, jitter: true)
        let executor = RetryExecutor(policy: policy)
        let cap = policy.exponentialDelay(forAttempt: 2) // = 4
        var prng = Mulberry32(seed: 99)
        for _ in 0..<50 {
            let delay = executor.computedDelay(forAttempt: 2, prng: &prng)
            XCTAssertGreaterThanOrEqual(delay, 0)
            XCTAssertLessThanOrEqual(delay, cap + 0.0001)
        }
    }

    func testComputedDelayJitterIsNeverNegative() {
        let policy = RetryPolicy(maxAttempts: 5, baseDelay: 0.5, maxDelay: 30, jitter: true)
        let executor = RetryExecutor(policy: policy)
        var prng = Mulberry32(seed: 7)
        for attempt in 0..<5 {
            let delay = executor.computedDelay(forAttempt: attempt, prng: &prng)
            XCTAssertGreaterThanOrEqual(delay, 0, "Delay for attempt \(attempt) should be non-negative")
        }
    }

    func testComputedDelayJitterProducesVariance() {
        // Running with different seeds should produce different values (not always equal to cap)
        let policy = RetryPolicy(maxAttempts: 5, baseDelay: 1, maxDelay: 60, jitter: true)
        let executor = RetryExecutor(policy: policy)
        var values = Set<String>()
        for seed: UInt32 in 0..<20 {
            var prng = Mulberry32(seed: seed)
            let delay = executor.computedDelay(forAttempt: 3, prng: &prng)
            values.insert(String(format: "%.4f", delay))
        }
        // With 20 different seeds we should get at least 5 distinct values
        XCTAssertGreaterThan(values.count, 5)
    }

    // MARK: RetryExecutor — success on first attempt

    func testSucceedsOnFirstAttempt() async throws {
        let executor = RetryExecutor(policy: .noRetry)
        let counter = Counter()
        let result = try await executor.execute {
            await counter.increment()
            return 42
        }
        XCTAssertEqual(result, 42)
        let count = await counter.value
        XCTAssertEqual(count, 1)
    }

    // MARK: RetryExecutor — non-retryable error propagates immediately

    func testNonRetryableErrorPropagatesImmediately() async {
        let executor = RetryExecutor(
            policy: RetryPolicy(maxAttempts: 3, baseDelay: 0, maxDelay: 0, jitter: false)
        )
        let counter = Counter()
        do {
            _ = try await executor.execute {
                await counter.increment()
                throw URLError(.badURL)
            }
            XCTFail("Should have thrown")
        } catch {
            let count = await counter.value
            XCTAssertEqual(count, 1, "Should not retry on non-retryable error")
        }
    }

    // MARK: RetryExecutor — retryable error exhausts all attempts

    func testRetryableErrorExhaustsAttempts() async throws {
        let policy = RetryPolicy(maxAttempts: 3, baseDelay: 0, maxDelay: 0, jitter: false)
        let executor = RetryExecutor(policy: policy)
        let counter = Counter()
        do {
            _ = try await executor.execute {
                await counter.increment()
                throw URLError(.timedOut)
            }
            XCTFail("Should have thrown")
        } catch {
            let count = await counter.value
            XCTAssertEqual(count, 3, "Should have attempted exactly maxAttempts times")
        }
    }

    func testNetworkConnectionLostIsRetried() async throws {
        let policy = RetryPolicy(maxAttempts: 2, baseDelay: 0, maxDelay: 0, jitter: false)
        let executor = RetryExecutor(policy: policy)
        let counter = Counter()
        do {
            _ = try await executor.execute {
                await counter.increment()
                throw URLError(.networkConnectionLost)
            }
            XCTFail("Should have thrown")
        } catch {
            let count = await counter.value
            XCTAssertEqual(count, 2)
        }
    }

    func testNotConnectedToInternetIsRetried() async throws {
        let policy = RetryPolicy(maxAttempts: 2, baseDelay: 0, maxDelay: 0, jitter: false)
        let executor = RetryExecutor(policy: policy)
        let counter = Counter()
        do {
            _ = try await executor.execute {
                await counter.increment()
                throw URLError(.notConnectedToInternet)
            }
            XCTFail("Should have thrown")
        } catch {
            let count = await counter.value
            XCTAssertEqual(count, 2)
        }
    }

    func testDataNotAllowedIsRetried() async throws {
        let policy = RetryPolicy(maxAttempts: 2, baseDelay: 0, maxDelay: 0, jitter: false)
        let executor = RetryExecutor(policy: policy)
        let counter = Counter()
        do {
            _ = try await executor.execute {
                await counter.increment()
                throw URLError(.dataNotAllowed)
            }
            XCTFail("Should have thrown")
        } catch {
            let count = await counter.value
            XCTAssertEqual(count, 2)
        }
    }

    // MARK: RetryExecutor — succeeds on retry

    func testSucceedsOnSecondAttempt() async throws {
        let policy = RetryPolicy(maxAttempts: 3, baseDelay: 0, maxDelay: 0, jitter: false)
        let executor = RetryExecutor(policy: policy)
        let counter = Counter()
        let result = try await executor.execute {
            await counter.increment()
            let n = await counter.value
            if n < 2 { throw URLError(.timedOut) }
            return "ok"
        }
        XCTAssertEqual(result, "ok")
        let count = await counter.value
        XCTAssertEqual(count, 2)
    }

    // MARK: RetryExecutor — HTTP response variant

    func testHTTP503IsRetriedViaResponseVariant() async throws {
        let policy = RetryPolicy(maxAttempts: 3, baseDelay: 0, maxDelay: 0, jitter: false)
        let executor = RetryExecutor(policy: policy)
        let counter = Counter()
        do {
            _ = try await executor.execute { () -> (String, HTTPURLResponse) in
                await counter.increment()
                let response = HTTPURLResponse(
                    url: URL(string: "https://example.com")!,
                    statusCode: 503,
                    httpVersion: "HTTP/1.1",
                    headerFields: nil
                )!
                return ("body", response)
            }
            XCTFail("Should have thrown after exhausting attempts")
        } catch {
            let count = await counter.value
            XCTAssertEqual(count, 3)
        }
    }

    func testHTTP200IsNotRetriedViaResponseVariant() async throws {
        let policy = RetryPolicy(maxAttempts: 3, baseDelay: 0, maxDelay: 0, jitter: false)
        let executor = RetryExecutor(policy: policy)
        let counter = Counter()
        let result = try await executor.execute { () -> (String, HTTPURLResponse) in
            await counter.increment()
            let response = HTTPURLResponse(
                url: URL(string: "https://example.com")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return ("success", response)
        }
        XCTAssertEqual(result.0, "success")
        let count = await counter.value
        XCTAssertEqual(count, 1)
    }

    // MARK: RetryExecutorError

    func testExhaustedErrorDescription() {
        let error = RetryExecutorError.exhausted(underlying: "HTTP 503")
        XCTAssertEqual(error, RetryExecutorError.exhausted(underlying: "HTTP 503"))
    }

    // MARK: Static convenience wrapper

    func testStaticConvenienceWrapperSucceeds() async throws {
        let result = try await RetryExecutor.execute(
            policy: RetryPolicy(maxAttempts: 1, baseDelay: 0, maxDelay: 0, jitter: false)
        ) {
            return "hello"
        }
        XCTAssertEqual(result, "hello")
    }

    func testStaticConvenienceWrapperThrowsAfterExhaust() async throws {
        let counter = Counter()
        do {
            _ = try await RetryExecutor.execute(
                policy: RetryPolicy(maxAttempts: 2, baseDelay: 0, maxDelay: 0, jitter: false)
            ) {
                await counter.increment()
                throw URLError(.timedOut)
            }
            XCTFail("Should have thrown")
        } catch {
            let count = await counter.value
            XCTAssertEqual(count, 2)
        }
    }

    // MARK: defaultSeed

    func testDefaultSeedReturnsUInt32() {
        let seed = defaultSeed()
        // Just verify it returns a valid UInt32 (non-crashing)
        _ = Mulberry32(seed: seed)
    }
}
