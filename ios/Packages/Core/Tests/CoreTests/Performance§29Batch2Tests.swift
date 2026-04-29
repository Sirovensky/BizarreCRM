import XCTest
import SwiftUI
@testable import Core

// §29 Performance batch 2 — unit tests for helpers shipped in actionplan/§29-batch2.
//
// Coverage:
//   A. ImageCacheSizeConfig — default values, tenant-size factory, clamp
//   B. NukePipelineTuning   — flag constants, thumbnailURL transform
//   C. LazyListHelpers      — ListPaginationState equality, LoadMoreTrigger body
//   D. SignpostInterval     — measureSync returns value + non-negative elapsed

// MARK: - A. ImageCacheSizeConfig

final class ImageCacheSizeConfigTests: XCTestCase {

    // A1: Default initialiser uses spec-mandated values (§29.3).
    func test_defaults_matchSpec() {
        let cfg = ImageCacheSizeConfig()
        XCTAssertEqual(cfg.memoryBytes,      80 * 1024 * 1024,         "memory default 80 MB")
        XCTAssertEqual(cfg.thumbDiskBytes,  500 * 1024 * 1024,         "thumb default 500 MB")
        XCTAssertEqual(cfg.fullResDiskBytes, 2 * 1024 * 1024 * 1024,   "full-res default 2 GB")
    }

    // A2: forTenantSize(.small) returns 1 GB full-res cap.
    func test_tenantSize_small_fullRes1GB() {
        let cfg = ImageCacheSizeConfig.forTenantSize(.small)
        XCTAssertEqual(cfg.fullResDiskBytes, 1 * 1024 * 1024 * 1024)
    }

    // A3: forTenantSize(.xlarge) returns 10 GB full-res cap + 160 MB memory.
    func test_tenantSize_xlarge_fullRes10GB_memory160MB() {
        let cfg = ImageCacheSizeConfig.forTenantSize(.xlarge)
        XCTAssertEqual(cfg.fullResDiskBytes, 10 * 1024 * 1024 * 1024)
        XCTAssertEqual(cfg.memoryBytes,      160 * 1024 * 1024)
    }

    // A4: clamped() brings a too-small full-res cap up to the minimum 500 MB.
    func test_clamped_bringsBelowMinUpToMin() {
        var cfg = ImageCacheSizeConfig()
        cfg.fullResDiskBytes = 100 * 1024 * 1024   // 100 MB — below minimum
        let clamped = cfg.clamped()
        XCTAssertEqual(clamped.fullResDiskBytes, ImageCacheSizeConfig.fullResMinBytes)
    }

    // A5: clamped() brings an over-max full-res cap down to 20 GB.
    func test_clamped_bringsAboveMaxDownToMax() {
        var cfg = ImageCacheSizeConfig()
        cfg.fullResDiskBytes = 100 * 1024 * 1024 * 1024  // 100 GB — above max
        let clamped = cfg.clamped()
        XCTAssertEqual(clamped.fullResDiskBytes, ImageCacheSizeConfig.fullResMaxBytes)
    }

    // A6: clamped() is a no-op for an in-range value.
    func test_clamped_inRange_unchanged() {
        let cfg = ImageCacheSizeConfig.forTenantSize(.medium)  // 3 GB — in range
        XCTAssertEqual(cfg.clamped().fullResDiskBytes, cfg.fullResDiskBytes)
    }

    // A7: TenantSizeHint raw values match server contract.
    func test_tenantSizeHint_rawValues() {
        XCTAssertEqual(TenantSizeHint.small.rawValue,  "s")
        XCTAssertEqual(TenantSizeHint.medium.rawValue, "m")
        XCTAssertEqual(TenantSizeHint.large.rawValue,  "l")
        XCTAssertEqual(TenantSizeHint.xlarge.rawValue, "xl")
    }
}

// MARK: - B. NukePipelineTuning

final class NukePipelineTuningTests: XCTestCase {

    // B1: Progressive decoding is enabled by default.
    func test_progressiveDecodingEnabled() {
        XCTAssertTrue(NukePipelineOptions.isProgressiveDecodingEnabled)
    }

    // B2: Deduplication is enabled (§29.7 request coalescing).
    func test_deduplicationEnabled() {
        XCTAssertTrue(NukePipelineOptions.isDeduplicationEnabled)
    }

    // B3: Rate limiter is enabled.
    func test_rateLimiterEnabled() {
        XCTAssertTrue(NukePipelineOptions.isRateLimiterEnabled)
    }

    // B4: thumbnailURL appends w= and scale= query params.
    func test_thumbnailURL_appendsWidthAndScale() throws {
        let base = try XCTUnwrap(URL(string: "https://cdn.example.com/photos/abc.jpg"))
        let url = NukePipelineOptions.thumbnailURL(for: base, widthPts: 120, scale: 2)
        let comps = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = comps.queryItems ?? []
        let w     = items.first(where: { $0.name == "w" })?.value
        let scale = items.first(where: { $0.name == "scale" })?.value
        XCTAssertEqual(w,     "240", "w = widthPts × scale")
        XCTAssertEqual(scale, "2")
    }

    // B5: thumbnailURL replaces an existing w= param instead of duplicating it.
    func test_thumbnailURL_replacesExistingWParam() throws {
        let base = try XCTUnwrap(URL(string: "https://cdn.example.com/photos/abc.jpg?w=99"))
        let url = NukePipelineOptions.thumbnailURL(for: base, widthPts: 60, scale: 3)
        let comps = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let wValues = comps.queryItems?.filter { $0.name == "w" }.map { $0.value } ?? []
        XCTAssertEqual(wValues.count, 1, "Must not duplicate w= param")
        XCTAssertEqual(wValues.first ?? "", "180", "w = 60 × 3")
    }

    // B6: Disk cache names are non-empty and distinct.
    func test_diskCacheNames_nonEmptyAndDistinct() {
        XCTAssertFalse(NukePipelineOptions.thumbnailDiskCacheName.isEmpty)
        XCTAssertFalse(NukePipelineOptions.fullResDiskCacheName.isEmpty)
        XCTAssertNotEqual(
            NukePipelineOptions.thumbnailDiskCacheName,
            NukePipelineOptions.fullResDiskCacheName
        )
    }

    // B7: Visible-row priority > prefetch priority (higher = more urgent).
    func test_priorityOrdering_visibleHigherThanPrefetch() {
        XCTAssertGreaterThan(
            NukePipelineOptions.visibleRowPriorityRaw,
            NukePipelineOptions.prefetchPriorityRaw
        )
    }
}

// MARK: - C. LazyListHelpers — ListPaginationState

final class LazyListHelpersTests: XCTestCase {

    // C1: .loading equates to itself.
    func test_paginationState_loading_equatable() {
        XCTAssertEqual(ListPaginationState.loading, ListPaginationState.loading)
    }

    // C2: .partial with identical counts equates.
    func test_paginationState_partial_equatable() {
        let a = ListPaginationState.partial(shown: 50, total: 200)
        let b = ListPaginationState.partial(shown: 50, total: 200)
        XCTAssertEqual(a, b)
    }

    // C3: .partial with different counts does not equate.
    func test_paginationState_partial_notEqual_differentCounts() {
        let a = ListPaginationState.partial(shown: 50, total: 200)
        let b = ListPaginationState.partial(shown: 51, total: 200)
        XCTAssertNotEqual(a, b)
    }

    // C4: .end equates to itself.
    func test_paginationState_end_equatable() {
        XCTAssertEqual(ListPaginationState.end, ListPaginationState.end)
    }

    // C5: .offline with same params equates.
    func test_paginationState_offline_equatable() {
        let a = ListPaginationState.offline(cached: 30, lastSyncedAgo: "2h ago")
        let b = ListPaginationState.offline(cached: 30, lastSyncedAgo: "2h ago")
        XCTAssertEqual(a, b)
    }

    // C6: Different states do not equate.
    func test_paginationState_differentVariants_notEqual() {
        XCTAssertNotEqual(ListPaginationState.loading, ListPaginationState.end)
    }

    // C7: LoadMoreTrigger renders without crash (body is a Color.clear frame).
    func test_loadMoreTrigger_bodyCompiles() {
        var triggered = false
        let trigger = LoadMoreTrigger(onTrigger: { triggered = true })
        // Confirm the body produces a View (type-check is sufficient).
        let body: some View = trigger.body
        _ = body
        // onTrigger not called by construction — only by onAppear in a host.
        XCTAssertFalse(triggered)
    }
}

// MARK: - D. SignpostInterval

final class SignpostIntervalTests: XCTestCase {

    // D1: measureSync returns the value produced by the body closure.
    func test_measureSync_returnsBodyValue() {
        let result = SignpostInterval.measureSync("test.measureSync") {
            42
        }
        XCTAssertEqual(result, 42)
    }

    // D2: measureSync elapsed time is non-negative.
    func test_measureSync_elapsedIsNonNegative() {
        var elapsed: Double = -1
        let interval = SignpostInterval(name: "test.interval")
        elapsed = interval.end()
        XCTAssertGreaterThanOrEqual(elapsed, 0)
    }

    // D3: measure(_:body:) async returns value correctly.
    func test_measure_async_returnsBodyValue() async {
        let result = await SignpostInterval.measure("test.asyncMeasure") {
            "hello"
        }
        XCTAssertEqual(result, "hello")
    }

    // D4: measureSync propagates thrown errors.
    func test_measureSync_rethrowsError() {
        struct Boom: Error {}
        XCTAssertThrowsError(
            try SignpostInterval.measureSync("test.throws") { throw Boom() }
        )
    }

    // D5: Multiple calls to end() on separate intervals each return ≥ 0.
    func test_multipleIntervals_allReturnNonNegativeElapsed() {
        for i in 0..<5 {
            let interval = SignpostInterval(name: "test.multi")
            let ms = interval.end()
            XCTAssertGreaterThanOrEqual(ms, 0, "iteration \(i)")
        }
    }
}
