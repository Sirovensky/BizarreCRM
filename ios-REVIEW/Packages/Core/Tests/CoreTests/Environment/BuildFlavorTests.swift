import Testing
@testable import Core

// §77 Environment & Build Flavor helpers — unit tests for BuildFlavor
//
// Coverage targets:
//   - All three detection paths (bundle ID suffix, bundle name, fallback)
//   - All three flavors round-tripped through detect(from:)
//   - Convenience properties (isProduction, isNonProduction, label)
//   - CaseIterable / RawRepresentable contracts

// MARK: - Stub BundleInfoProvider

struct StubBundle: BundleInfoProvider, Sendable {
    let bundleIdentifier: String?
    let bundleName: String?

    init(id: String? = nil, name: String? = nil) {
        bundleIdentifier = id
        bundleName = name
    }
}

// MARK: - Tests

@Suite("BuildFlavor detection")
struct BuildFlavorDetectionTests {

    // MARK: Bundle-ID–based detection

    @Test("exact production bundle ID → .production")
    func exactProductionBundleID() {
        let flavor = BuildFlavor.detect(from: StubBundle(id: "com.bizarrecrm"))
        #expect(flavor == .production)
    }

    @Test(".staging suffix → .staging")
    func stagingSuffix() {
        let flavor = BuildFlavor.detect(from: StubBundle(id: "com.bizarrecrm.staging"))
        #expect(flavor == .staging)
    }

    @Test(".dev suffix → .development")
    func devSuffix() {
        let flavor = BuildFlavor.detect(from: StubBundle(id: "com.bizarrecrm.dev"))
        #expect(flavor == .development)
    }

    @Test("staging suffix wins over production-matching name")
    func stagingSuffixWinsOverName() {
        let flavor = BuildFlavor.detect(from: StubBundle(id: "com.bizarrecrm.staging", name: "BizarreCRM"))
        #expect(flavor == .staging)
    }

    // MARK: Bundle-name fallback

    @Test("name containing 'staging' (case-insensitive) → .staging")
    func nameStagingCaseInsensitive() {
        let flavor = BuildFlavor.detect(from: StubBundle(id: nil, name: "BizarreCRM Staging"))
        #expect(flavor == .staging)

        let lowerFlavor = BuildFlavor.detect(from: StubBundle(id: nil, name: "bizarrecrm staging"))
        #expect(lowerFlavor == .staging)
    }

    @Test("name containing 'dev' → .development")
    func nameDevFallback() {
        let flavor = BuildFlavor.detect(from: StubBundle(id: nil, name: "BizarreCRM Dev"))
        #expect(flavor == .development)
    }

    @Test("unknown bundle ID, matching name → name wins")
    func unknownBundleIDNameFallback() {
        let flavor = BuildFlavor.detect(from: StubBundle(id: "com.other.app", name: "BizarreCRM Dev"))
        // Bundle ID doesn't match production or suffixes, drops to name
        #expect(flavor == .development)
    }

    // MARK: Fallback to development

    @Test("nil bundle ID and nil name → .development")
    func nilBothFallback() {
        let flavor = BuildFlavor.detect(from: StubBundle(id: nil, name: nil))
        #expect(flavor == .development)
    }

    @Test("unrecognised bundle ID, no name → .development")
    func unknownFallback() {
        let flavor = BuildFlavor.detect(from: StubBundle(id: "com.unrelated", name: nil))
        #expect(flavor == .development)
    }
}

@Suite("BuildFlavor convenience properties")
struct BuildFlavorConvenienceTests {

    @Test("production.isProduction == true")
    func productionIsProduction() {
        #expect(BuildFlavor.production.isProduction)
    }

    @Test("staging.isProduction == false")
    func stagingNotProduction() {
        #expect(!BuildFlavor.staging.isProduction)
    }

    @Test("development.isProduction == false")
    func developmentNotProduction() {
        #expect(!BuildFlavor.development.isProduction)
    }

    @Test("isNonProduction is inverse of isProduction")
    func isNonProductionInverse() {
        for flavor in BuildFlavor.allCases {
            #expect(flavor.isNonProduction == !flavor.isProduction)
        }
    }

    @Test("labels are non-empty and distinct")
    func labelsDistinct() {
        let labels = BuildFlavor.allCases.map(\.label)
        #expect(Set(labels).count == BuildFlavor.allCases.count)
        for label in labels {
            #expect(!label.isEmpty)
        }
    }

    @Test("rawValues round-trip through init")
    func rawValueRoundTrip() {
        for flavor in BuildFlavor.allCases {
            let reconstructed = BuildFlavor(rawValue: flavor.rawValue)
            #expect(reconstructed == flavor)
        }
    }
}
