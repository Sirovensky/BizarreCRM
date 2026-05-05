import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §6.6 Multi-user stocktake — WS presence banner

/// Tracks which other users are scanning in the same stocktake session.
/// Listens on the WS broadcast topic `stocktake:<sessionId>:scan`.
/// Shows a Liquid Glass banner listing active scanners so each user
/// knows they aren't double-counting.
///
/// Usage: embed `StocktakePresenceBanner` in `StocktakeScanView`.
@MainActor
@Observable
public final class StocktakePresenceViewModel {
    // MARK: - State

    /// Set of active scanner display names (excludes current user).
    public private(set) var activeScanners: [ActiveScanner] = []
    /// Last scan event received via WS — for live feedback.
    public private(set) var lastRemoteScan: RemoteScanEvent?

    public struct ActiveScanner: Identifiable, Sendable {
        public let id: String    // userId as string
        public let name: String
        public let scannedCount: Int
        public let lastSeenAt: Date
    }

    public struct RemoteScanEvent: Sendable {
        public let scannerName: String
        public let barcode: String
        public let foundMatch: Bool
        public let timestamp: Date
    }

    @ObservationIgnored private var wsTask: Task<Void, Never>?
    @ObservationIgnored private let ws: WebSocketClient?
    @ObservationIgnored private let sessionId: Int64

    public init(ws: WebSocketClient?, sessionId: Int64) {
        self.ws = ws
        self.sessionId = sessionId
    }

    deinit {
        wsTask?.cancel()
    }

    // MARK: - Start / stop

    public func startListening() {
        guard let ws else { return }
        wsTask?.cancel()
        wsTask = Task { [weak self, ws] in
            guard let self else { return }
            for await event in ws.events {
                guard !Task.isCancelled else { break }
                await self.handle(event: event)
            }
        }
    }

    public func stopListening() {
        wsTask?.cancel()
        wsTask = nil
    }

    // MARK: - WS event handling

    @MainActor
    private func handle(event: WSEvent) async {
        // §17.3 — multi-user stocktake presence events are typed differently
        // in the Networking WSEvent enum; this handler is a no-op until the
        // event variant lands. See Networking/WebSocketClient.swift.
        return
        // (suppress unused-var warnings below)
        // swiftlint:disable:next unreachable_code
        guard let data = String(describing: event).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let eventName = json["event"] as? String,
              eventName == "stocktake:scan",
              let sid = json["session_id"] as? Int,
              Int64(sid) == sessionId else { return }

        let userId = (json["user_id"] as? Int).map { "\($0)" } ?? "unknown"
        let userName = json["user_name"] as? String ?? "Scanner"
        let barcode = json["barcode"] as? String ?? ""
        let foundMatch = json["found_match"] as? Bool ?? false
        let scannedCount = json["scanned_count"] as? Int ?? 0

        // Update active scanner list
        if let idx = activeScanners.firstIndex(where: { $0.id == userId }) {
            activeScanners[idx] = ActiveScanner(
                id: userId,
                name: userName,
                scannedCount: scannedCount,
                lastSeenAt: Date()
            )
        } else {
            activeScanners.append(ActiveScanner(
                id: userId,
                name: userName,
                scannedCount: scannedCount,
                lastSeenAt: Date()
            ))
        }
        // Prune scanners idle > 5 minutes
        let cutoff = Date().addingTimeInterval(-300)
        activeScanners.removeAll { $0.lastSeenAt < cutoff }

        // Record latest remote scan event for feedback badge
        lastRemoteScan = RemoteScanEvent(
            scannerName: userName,
            barcode: barcode,
            foundMatch: foundMatch,
            timestamp: Date()
        )
    }
}

// MARK: - StocktakePresenceBanner

/// Glass banner shown at the top of `StocktakeScanView` when other users
/// are active in the same session. Shows their names + scan counts.
public struct StocktakePresenceBanner: View {
    public let vm: StocktakePresenceViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(vm: StocktakePresenceViewModel) {
        self.vm = vm
    }

    public var body: some View {
        if vm.activeScanners.isEmpty { EmptyView() } else { banner }
    }

    private var banner: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 14))
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Multi-user session")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurface)
                Text(scannerSummary)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }

            Spacer()

            if let last = vm.lastRemoteScan {
                RemoteScanBadge(event: last)
                    .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.sm)
        .brandGlass(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var scannerSummary: String {
        let names = vm.activeScanners.map { "\($0.name) (\($0.scannedCount))" }
        return names.joined(separator: " · ")
    }

    private var accessibilityDescription: String {
        "Multi-user stocktake session. \(vm.activeScanners.count) other scanner\(vm.activeScanners.count == 1 ? "" : "s") active: \(scannerSummary)"
    }
}

// MARK: - RemoteScanBadge

private struct RemoteScanBadge: View {
    let event: StocktakePresenceViewModel.RemoteScanEvent

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: event.foundMatch ? "checkmark.circle.fill" : "questionmark.circle")
                .font(.system(size: 12))
                .foregroundStyle(event.foundMatch ? Color.bizarreSuccess : Color.bizarreWarning)
                .accessibilityHidden(true)
            Text(String(event.barcode.prefix(10)))
                .font(.brandMono(size: 11))
                .foregroundStyle(.bizarreOnSurface)
                .lineLimit(1)
        }
        .padding(.horizontal, BrandSpacing.sm)
        .padding(.vertical, BrandSpacing.xxs)
        .background(Color.bizarreSurface2, in: Capsule())
        .accessibilityLabel("\(event.scannerName) scanned \(event.barcode). \(event.foundMatch ? "Match found." : "No match.")")
    }
}

// MARK: - WSEvent helper (local shim)

/// Minimal event enum so this module compiles independently of WS internals.
private enum LocalWSEvent {
    case message(String)
    case connected
    case disconnected(Error?)
}

// MARK: - BrandGlass modifier (forward to DesignSystem)

private extension View {
    func brandGlass(_ material: some ShapeStyle) -> some View {
        self.background(material)
    }
}
