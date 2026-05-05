import Foundation
import Testing
@testable import Core

// §77 Environment & Build Flavor helpers — unit tests for DiagnosticsExporter
//
// Coverage targets:
//   - makeSnapshot() captures correct flavor, version strings, device info
//   - exportJSON() produces valid JSON decodable back to DiagnosticsSnapshot
//   - write(to:) creates a file with the expected content
//   - capturedAt is ISO-8601 formatted
//   - featureFlags dictionary is present and non-empty
//   - No PII fields appear in the output

// MARK: - Test double

struct StubDeviceInfo: DeviceInfoProviding, Sendable {
    let systemName: String
    let systemVersion: String
    let model: String
    let isSimulator: Bool
}

// MARK: - Tests

@Suite("DiagnosticsExporter — snapshot content")
struct DiagnosticsExporterSnapshotTests {

    private func makeExporter(
        flavor: BuildFlavor = .staging,
        fixedDate: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> DiagnosticsExporter {
        DiagnosticsExporter(
            resolver: FeatureFlagResolver(flavor: flavor),
            flavor: flavor,
            deviceInfoProvider: StubDeviceInfo(
                systemName: "iOS",
                systemVersion: "17.4",
                model: "iPhone",
                isSimulator: true
            ),
            dateProvider: { fixedDate }
        )
    }

    @Test("flavor is captured correctly")
    func snapshotFlavor() {
        let snapshot = makeExporter(flavor: .staging).makeSnapshot()
        #expect(snapshot.environment.flavor == BuildFlavor.staging.rawValue)
    }

    @Test("development flavor captured")
    func snapshotDevelopmentFlavor() {
        let snapshot = makeExporter(flavor: .development).makeSnapshot()
        #expect(snapshot.environment.flavor == BuildFlavor.development.rawValue)
    }

    @Test("device info is captured without PII")
    func snapshotDeviceInfo() {
        let snapshot = makeExporter().makeSnapshot()
        #expect(snapshot.device.systemName == "iOS")
        #expect(snapshot.device.systemVersion == "17.4")
        #expect(snapshot.device.model == "iPhone")
        #expect(snapshot.device.isSimulator == true)
    }

    @Test("capturedAt is valid ISO-8601 date string")
    func snapshotCapturedAt() {
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = makeExporter(fixedDate: fixedDate).makeSnapshot()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let parsed = formatter.date(from: snapshot.capturedAt)
        #expect(parsed != nil)
        // Allow 1-second delta for any timezone rounding
        #expect(abs((parsed?.timeIntervalSince1970 ?? 0) - fixedDate.timeIntervalSince1970) < 1)
    }

    @Test("featureFlags dictionary is non-empty and contains all flags")
    func snapshotFeatureFlags() {
        let snapshot = makeExporter().makeSnapshot()
        #expect(!snapshot.featureFlags.isEmpty)
        #expect(snapshot.featureFlags.count == FeatureFlag.allCases.count)
        for flag in FeatureFlag.allCases {
            #expect(snapshot.featureFlags[flag.rawValue] != nil)
        }
    }

    @Test("snapshot equality is stable for same inputs")
    func snapshotEquality() {
        let exporter = makeExporter()
        let a = exporter.makeSnapshot()
        let b = exporter.makeSnapshot()
        #expect(a == b)
    }
}

@Suite("DiagnosticsExporter — JSON serialisation")
struct DiagnosticsExporterJSONTests {

    private func makeExporter(flavor: BuildFlavor = .staging) -> DiagnosticsExporter {
        DiagnosticsExporter(
            resolver: FeatureFlagResolver(flavor: flavor),
            flavor: flavor,
            deviceInfoProvider: StubDeviceInfo(
                systemName: "iOS",
                systemVersion: "17.4",
                model: "Simulator",
                isSimulator: true
            ),
            dateProvider: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
    }

    @Test("exportJSON() returns valid non-empty data")
    func exportJSONNonEmpty() throws {
        let data = try makeExporter().exportJSON()
        #expect(!data.isEmpty)
    }

    @Test("exported JSON round-trips through decoder")
    func exportJSONRoundTrip() throws {
        let exporter = makeExporter()
        let data = try exporter.exportJSON()
        let decoded = try JSONDecoder().decode(DiagnosticsSnapshot.self, from: data)
        let original = exporter.makeSnapshot()
        #expect(decoded == original)
    }

    @Test("exported JSON is sorted and pretty-printed (contains newlines)")
    func exportJSONFormatting() throws {
        let data = try makeExporter().exportJSON()
        let text = String(decoding: data, as: UTF8.self)
        // pretty-printed JSON has newlines
        #expect(text.contains("\n"))
    }

    @Test("exported JSON does not contain device name (PII)")
    func exportJSONNoPIIDeviceName() throws {
        let data = try makeExporter().exportJSON()
        let text = String(decoding: data, as: UTF8.self)
        // should not contain "deviceName" or "name" as a PII field
        #expect(!text.contains("\"deviceName\""))
    }

    @Test("write(to:) creates a file with correct content")
    func writeToURL() throws {
        let exporter = makeExporter()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("diag-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        try exporter.write(to: url)

        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(DiagnosticsSnapshot.self, from: data)
        #expect(decoded == exporter.makeSnapshot())
    }
}

@Suite("DiagnosticsExporter — PII audit")
struct DiagnosticsExporterPIITests {

    @Test("snapshot fields do not include user-identifiable keys")
    func noPIIFields() throws {
        let exporter = DiagnosticsExporter(
            resolver: FeatureFlagResolver(flavor: .development),
            flavor: .development,
            deviceInfoProvider: StubDeviceInfo(
                systemName: "iOS",
                systemVersion: "17.4",
                model: "Simulator",
                isSimulator: true
            ),
            dateProvider: { Date() }
        )
        let data = try exporter.exportJSON()
        let text = String(decoding: data, as: UTF8.self)

        // Negative assertions: PII field names must not appear in output
        let piiFieldNames = ["email", "phone", "userName", "userId", "token",
                             "authToken", "ipAddress", "carrier", "advertisingId"]
        for fieldName in piiFieldNames {
            let containsPII = text.lowercased().contains("\"\(fieldName.lowercased())\"")
            #expect(!containsPII)
        }
    }
}
