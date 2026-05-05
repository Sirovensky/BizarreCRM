import Testing
import Foundation
@testable import Settings
import Core

// MARK: - DiagnosticsBundleBuilderTests

@Suite("DiagnosticsBundleBuilder")
struct DiagnosticsBundleBuilderTests {

    // MARK: - Stub DeviceInfoProvider

    struct StubDeviceInfo: DeviceInfoProvider, Sendable {
        func currentInfo() -> DeviceInfo {
            DeviceInfo(
                appVersion: "1.2.3",
                buildNumber: "42",
                iosVersion: "26.0",
                deviceModel: "iPhone16,2"
            )
        }
    }

    // MARK: - Build tests

    @Test("Build returns correct app version from stub")
    func buildAppVersion() async {
        let store = BreadcrumbStore()
        let builder = DiagnosticsBundleBuilder(
            breadcrumbStore: store,
            deviceInfoProvider: StubDeviceInfo()
        )
        let bundle = await builder.build()
        #expect(bundle.appVersion == "1.2.3")
        #expect(bundle.buildNumber == "42")
        #expect(bundle.iosVersion == "26.0")
        #expect(bundle.deviceModel == "iPhone16,2")
    }

    @Test("Build includes tenantSlug when provided")
    func buildWithTenantSlug() async {
        let store = BreadcrumbStore()
        let builder = DiagnosticsBundleBuilder(
            breadcrumbStore: store,
            deviceInfoProvider: StubDeviceInfo()
        )
        let bundle = await builder.build(tenantSlug: "acme-repair")
        #expect(bundle.tenantSlug == "acme-repair")
    }

    @Test("Build returns nil tenantSlug when not provided")
    func buildWithoutTenantSlug() async {
        let store = BreadcrumbStore()
        let builder = DiagnosticsBundleBuilder(
            breadcrumbStore: store,
            deviceInfoProvider: StubDeviceInfo()
        )
        let bundle = await builder.build()
        #expect(bundle.tenantSlug == nil)
    }

    // MARK: - Redaction verification

    @Test("Breadcrumbs with PII are redacted in the bundle")
    func piiRedactionInBreadcrumbs() async {
        let store = BreadcrumbStore()
        await store.push(Breadcrumb(
            timestamp: Date(),
            level: .info,
            category: "auth",
            message: "User email: test@example.com",
            metadata: nil
        ))
        let builder = DiagnosticsBundleBuilder(
            breadcrumbStore: store,
            deviceInfoProvider: StubDeviceInfo()
        )
        let bundle = await builder.build()
        for crumb in bundle.recentBreadcrumbs {
            #expect(!crumb.message.contains("test@example.com"), "PII email not redacted: \(crumb.message)")
        }
    }

    @Test("Bundle includes at most 20 breadcrumbs")
    func bundleAtMost20Crumbs() async {
        let store = BreadcrumbStore()
        for i in 0..<30 {
            await store.push(Breadcrumb(
                timestamp: Date(),
                level: .debug,
                category: "test",
                message: "crumb \(i)",
                metadata: nil
            ))
        }
        let builder = DiagnosticsBundleBuilder(
            breadcrumbStore: store,
            deviceInfoProvider: StubDeviceInfo()
        )
        let bundle = await builder.build()
        #expect(bundle.recentBreadcrumbs.count <= 20)
    }

    @Test("Bundle has empty breadcrumbs when store is empty")
    func emptyBreadcrumbs() async {
        let store = BreadcrumbStore()
        let builder = DiagnosticsBundleBuilder(
            breadcrumbStore: store,
            deviceInfoProvider: StubDeviceInfo()
        )
        let bundle = await builder.build()
        #expect(bundle.recentBreadcrumbs.isEmpty)
    }

    // MARK: - JSON attachment

    @Test("buildJSONAttachment produces valid JSON")
    func jsonAttachmentIsValidJSON() async throws {
        let store = BreadcrumbStore()
        let builder = DiagnosticsBundleBuilder(
            breadcrumbStore: store,
            deviceInfoProvider: StubDeviceInfo()
        )
        let data = try await builder.buildJSONAttachment()
        #expect(!data.isEmpty)
        // Must be valid JSON
        let obj = try JSONSerialization.jsonObject(with: data)
        #expect(obj is [String: Any])
    }

    @Test("JSON attachment contains appVersion key")
    func jsonContainsAppVersion() async throws {
        let store = BreadcrumbStore()
        let builder = DiagnosticsBundleBuilder(
            breadcrumbStore: store,
            deviceInfoProvider: StubDeviceInfo()
        )
        let data = try await builder.buildJSONAttachment()
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(dict["appVersion"] != nil)
    }

    @Test("Breadcrumb timestamps are ISO8601 strings")
    func breadcrumbTimestampsAreISO8601() async {
        let store = BreadcrumbStore()
        await store.push(Breadcrumb(
            timestamp: Date(),
            level: .info,
            category: "test",
            message: "hello",
            metadata: nil
        ))
        let builder = DiagnosticsBundleBuilder(
            breadcrumbStore: store,
            deviceInfoProvider: StubDeviceInfo()
        )
        let bundle = await builder.build()
        for crumb in bundle.recentBreadcrumbs {
            #expect(crumb.timestamp.contains("T"), "Expected ISO8601 timestamp, got: \(crumb.timestamp)")
        }
    }
}
