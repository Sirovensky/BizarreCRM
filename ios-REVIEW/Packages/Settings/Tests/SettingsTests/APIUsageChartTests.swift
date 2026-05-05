import Testing
import Foundation
@testable import Settings

// MARK: - APIUsageChart data processing tests

@Suite("APIUsageChart.process(_:)")
struct APIUsageChartTests {

    private func makeBucket(daysAgo: Int, count: Int) -> DailyBucket {
        let calendar = Calendar.current
        let date = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: Date()))!
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return DailyBucket(date: formatter.string(from: date), count: count)
    }

    @Test("Empty input produces 30 zero-filled buckets")
    func emptyInputProduces30Buckets() {
        let result = APIUsageChart.process([])
        #expect(result.count == 30)
        #expect(result.allSatisfy { $0.count == 0 })
    }

    @Test("Today bucket count is preserved")
    func todayBucketPreserved() {
        let today = makeBucket(daysAgo: 0, count: 42)
        let result = APIUsageChart.process([today])
        let last = result.last
        #expect(last?.count == 42)
    }

    @Test("Bucket 15 days ago is at correct index")
    func bucket15DaysAgoAtCorrectIndex() {
        let bucket = makeBucket(daysAgo: 15, count: 99)
        let result = APIUsageChart.process([bucket])
        // Index 0 = 29 days ago, index 14 = 15 days ago
        #expect(result[14].count == 99)
    }

    @Test("Multiple buckets are placed correctly")
    func multipleBucketsPlacedCorrectly() {
        let b1 = makeBucket(daysAgo: 0, count: 10)
        let b2 = makeBucket(daysAgo: 5, count: 50)
        let b3 = makeBucket(daysAgo: 29, count: 200)
        let result = APIUsageChart.process([b1, b2, b3])
        #expect(result.count == 30)
        #expect(result.last?.count == 10)       // today
        #expect(result[24].count == 50)         // 5 days ago
        #expect(result[0].count == 200)         // 29 days ago
    }

    @Test("Missing days are filled with zero")
    func missingDaysFilledWithZero() {
        let today = makeBucket(daysAgo: 0, count: 5)
        let result = APIUsageChart.process([today])
        let nonToday = result.dropLast()
        #expect(nonToday.allSatisfy { $0.count == 0 })
    }

    @Test("All buckets have non-empty label")
    func allBucketsHaveLabel() {
        let result = APIUsageChart.process([])
        #expect(result.allSatisfy { !$0.label.isEmpty })
    }

    @Test("All buckets have unique IDs")
    func allBucketsUniqueIDs() {
        let result = APIUsageChart.process([])
        let ids = Set(result.map(\.id))
        #expect(ids.count == result.count)
    }

    @Test("Input bucket with count 0 stays at 0")
    func zeroBucketPreserved() {
        let zero = makeBucket(daysAgo: 3, count: 0)
        let result = APIUsageChart.process([zero])
        #expect(result[26].count == 0)
    }

    @Test("Large count values are handled without overflow")
    func largeCountHandled() {
        let large = makeBucket(daysAgo: 0, count: 1_000_000)
        let result = APIUsageChart.process([large])
        #expect(result.last?.count == 1_000_000)
    }

    @Test("Duplicate date entries — last one wins via dict overwrite")
    func duplicateDateLastWins() {
        let b1 = makeBucket(daysAgo: 0, count: 10)
        let b2 = makeBucket(daysAgo: 0, count: 99)
        let result = APIUsageChart.process([b1, b2])
        // Only one entry for today exists; dict keeps last-set value
        #expect(result.last?.count == 99)
    }
}
