#if canImport(UIKit)
import Foundation
import Network
import Core

// MARK: - BonjourPrinterBrowser
//
// §17 Bonjour / mDNS printer discovery.
//
// Browses for printers on the local network using `NWBrowser` and surfaces them
// as ``DiscoveredPrinter`` values. The caller (e.g. `PrinterSettingsViewModel`)
// subscribes via `AsyncStream<[DiscoveredPrinter]>` and refreshes the UI.
//
// Service types browsed:
//   - `_ipp._tcp`         — IPP printers (AirPrint and most network printers)
//   - `_printer._tcp`     — Legacy LPD printers
//   - `_bizarre._tcp`     — BizarreCRM-branded smart accessories (future)
//
// Permissions: `NSLocalNetworkUsageDescription` must be in Info.plist (done
// via `scripts/write-info-plist.sh`). Trigger is the first browse call.
//
// Auto-refresh: the browser pushes updates continuously; the stream never
// completes until the caller cancels. An explicit `refresh()` call restarts
// the underlying browsers to flush the cache.

// MARK: - Discovered Printer

/// A printer found via Bonjour on the local network.
public struct DiscoveredPrinter: Identifiable, Sendable, Hashable {

    /// Stable ID: service type + service name.
    public let id: String
    /// Human-readable service name (e.g. "Star TSP100IV").
    public let name: String
    /// Bonjour service type ("_ipp._tcp", "_printer._tcp", "_bizarre._tcp").
    public let serviceType: String
    /// Resolved host name (nil until `resolve()` completes).
    public let host: String?
    /// Resolved port (nil until `resolve()` completes).
    public let port: Int?

    public init(id: String, name: String, serviceType: String, host: String? = nil, port: Int? = nil) {
        self.id = id
        self.name = name
        self.serviceType = serviceType
        self.host = host
        self.port = port
    }

    /// Icon name per service type for the picker UI.
    public var systemImageName: String {
        switch serviceType {
        case "_ipp._tcp", "_printer._tcp": return "printer"
        case "_bizarre._tcp":              return "bolt.horizontal"
        default:                           return "questionmark.circle"
        }
    }

    /// Short label describing the service class.
    public var serviceLabel: String {
        switch serviceType {
        case "_ipp._tcp":     return "IPP / AirPrint"
        case "_printer._tcp": return "LPD Printer"
        case "_bizarre._tcp": return "BizarreCRM"
        default:              return serviceType
        }
    }
}

// MARK: - BonjourPrinterBrowserProtocol

public protocol BonjourPrinterBrowserProtocol: Sendable {
    /// Returns an `AsyncStream` that emits the current list of discovered printers
    /// whenever the list changes. The stream runs until cancelled.
    func discoveryStream() -> AsyncStream<[DiscoveredPrinter]>
    /// Restarts the underlying browsers (flushes stale results).
    func refresh() async
    /// Stops all browsing. The stream will receive one final empty emission.
    func stop() async
}

// MARK: - BonjourPrinterBrowser

public actor BonjourPrinterBrowser: BonjourPrinterBrowserProtocol {

    // MARK: - Constants

    private static let serviceTypes: [String] = [
        "_ipp._tcp",
        "_printer._tcp",
        "_bizarre._tcp",
    ]

    // MARK: - State

    private var browsers: [NWBrowser] = []
    private var discovered: [String: DiscoveredPrinter] = [:]
    private var continuation: AsyncStream<[DiscoveredPrinter]>.Continuation?

    // MARK: - Init

    public init() {}

    // MARK: - BonjourPrinterBrowserProtocol

    public func discoveryStream() -> AsyncStream<[DiscoveredPrinter]> {
        let stream = AsyncStream<[DiscoveredPrinter]> { [weak self] continuation in
            guard let self else {
                continuation.finish()
                return
            }
            Task {
                await self._setStream(continuation)
                await self._startBrowsing()
            }
        }
        return stream
    }

    public func refresh() async {
        _stopBrowsers()
        discovered.removeAll()
        emit()
        _startBrowsing()
    }

    public func stop() async {
        _stopBrowsers()
        discovered.removeAll()
        continuation?.yield([])
        continuation?.finish()
        continuation = nil
    }

    // MARK: - Private

    private func _setStream(_ continuation: AsyncStream<[DiscoveredPrinter]>.Continuation) {
        self.continuation = continuation
    }

    private func _startBrowsing() {
        for type in Self.serviceTypes {
            let descriptor = NWBrowser.Descriptor.bonjour(type: type, domain: "local.")
            let params = NWParameters()
            params.includePeerToPeer = false
            let browser = NWBrowser(for: descriptor, using: params)
            browser.stateUpdateHandler = { [weak self] _ in }
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                guard let self else { return }
                Task { await self._handleResults(results, serviceType: type) }
            }
            browser.start(queue: .global(qos: .utility))
            browsers.append(browser)
        }
        AppLog.hardware.info("BonjourPrinterBrowser: started browsing \(Self.serviceTypes.count) service type(s)")
    }

    private func _stopBrowsers() {
        browsers.forEach { $0.cancel() }
        browsers.removeAll()
    }

    private func _handleResults(_ results: Set<NWBrowser.Result>, serviceType: String) {
        // Remove stale entries for this service type
        let keysForType = discovered.keys.filter { $0.hasPrefix("\(serviceType)::") }
        keysForType.forEach { discovered.removeValue(forKey: $0) }

        for result in results {
            guard case .service(let name, _, _, _) = result.endpoint else { continue }
            let id = "\(serviceType)::\(name)"
            discovered[id] = DiscoveredPrinter(
                id: id,
                name: name,
                serviceType: serviceType
            )
        }
        emit()
        AppLog.hardware.debug("BonjourPrinterBrowser: \(discovered.count) printer(s) discovered")
    }

    private func emit() {
        continuation?.yield(Array(discovered.values).sorted { $0.name < $1.name })
    }
}

// MARK: - MockBonjourPrinterBrowser

/// Controllable test-double for `BonjourPrinterBrowserProtocol`.
public actor MockBonjourPrinterBrowser: BonjourPrinterBrowserProtocol {

    public var stubbedPrinters: [DiscoveredPrinter]
    public private(set) var refreshCallCount: Int = 0
    public private(set) var stopCallCount: Int = 0

    public init(stubbedPrinters: [DiscoveredPrinter] = []) {
        self.stubbedPrinters = stubbedPrinters
    }

    public func discoveryStream() -> AsyncStream<[DiscoveredPrinter]> {
        let printers = stubbedPrinters
        return AsyncStream { continuation in
            continuation.yield(printers)
            // Leave open; test controls completion via `stop()`.
        }
    }

    public func refresh() async {
        refreshCallCount += 1
    }

    public func stop() async {
        stopCallCount += 1
    }
}

#endif
