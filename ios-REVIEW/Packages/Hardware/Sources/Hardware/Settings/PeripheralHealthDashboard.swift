#if canImport(SwiftUI)
import SwiftUI
import Core

// MARK: - PeripheralHealthDashboard
//
// §17: "Settings → Hardware: per-station peripheral-health dashboard / logs"

// MARK: - PeripheralHealthEntry

/// One peripheral's current health status on a station.
public struct PeripheralHealthEntry: Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let kind: DeviceKind
    public let status: PeripheralHealthStatus
    public let batteryPercent: Int?
    public let lastSeenAt: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        kind: DeviceKind,
        status: PeripheralHealthStatus,
        batteryPercent: Int? = nil,
        lastSeenAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.status = status
        self.batteryPercent = batteryPercent
        self.lastSeenAt = lastSeenAt
    }
}

public enum PeripheralHealthStatus: Sendable {
    case online
    case offline
    case degraded(String)
    case notConfigured

    public var label: String {
        switch self {
        case .online:             return "Online"
        case .offline:            return "Offline"
        case .degraded(let msg):  return "Degraded: \(msg)"
        case .notConfigured:      return "Not configured"
        }
    }

    public var isOnline: Bool {
        if case .online = self { return true }
        return false
    }
}

// MARK: - PeripheralHealthDashboardView

/// Lists all peripherals bound to the active station with health badges.
///
/// iPhone: scrollable List.
/// iPad: same view in the detail pane of `HardwareSettingsView`.
///
/// §17: "Settings → Hardware: per-station peripheral-health dashboard / logs"
public struct PeripheralHealthDashboardView: View {

    public let stationName: String
    public let entries: [PeripheralHealthEntry]
    public let connectionLogs: [PeripheralConnectionLog]
    public let onRefresh: () async -> Void

    public init(
        stationName: String,
        entries: [PeripheralHealthEntry],
        connectionLogs: [PeripheralConnectionLog] = [],
        onRefresh: @escaping () async -> Void
    ) {
        self.stationName = stationName
        self.entries = entries
        self.connectionLogs = connectionLogs
        self.onRefresh = onRefresh
    }

    public var body: some View {
        List {
            // Station header
            Section {
                HStack {
                    Image(systemName: "display")
                        .foregroundStyle(.tint)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stationName)
                            .font(.headline)
                        Text(summaryText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Station: \(stationName). \(summaryText)")
            }

            // Peripheral health rows
            Section("PERIPHERALS") {
                if entries.isEmpty {
                    Text("No peripherals configured for this station.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .accessibilityLabel("No peripherals configured")
                } else {
                    ForEach(entries) { entry in
                        PeripheralHealthRow(entry: entry)
                    }
                }
            }

            // Connection log (last 10 events)
            if !connectionLogs.isEmpty {
                Section("RECENT EVENTS") {
                    ForEach(connectionLogs.prefix(10)) { log in
                        ConnectionLogRow(log: log)
                    }
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .navigationTitle("Peripheral Health")
        #if os(iOS)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await onRefresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh peripheral health status")
            }
        }
    }

    // MARK: - Summary

    private var summaryText: String {
        let online = entries.filter { $0.status.isOnline }.count
        let total = entries.count
        return "\(online)/\(total) peripherals online"
    }
}

// MARK: - PeripheralHealthRow

private struct PeripheralHealthRow: View {
    let entry: PeripheralHealthEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.kind.systemImageName)
                .foregroundStyle(statusColor)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.body)
                HStack(spacing: 6) {
                    Text(entry.status.label)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                    if let pct = entry.batteryPercent {
                        batteryChip(pct: pct)
                    }
                }
            }

            Spacer()

            if let date = entry.lastSeenAt {
                Text(date.formatted(.relative(presentation: .numeric)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var statusColor: Color {
        switch entry.status {
        case .online:       return .green
        case .offline:      return .red
        case .degraded:     return .orange
        case .notConfigured: return .secondary
        }
    }

    @ViewBuilder
    private func batteryChip(pct: Int) -> some View {
        let low = pct < 20
        Label("\(pct)%", systemImage: "battery.50percent")
            .font(.caption2)
            .foregroundStyle(low ? .red : .secondary)
            .accessibilityLabel(low ? "Low battery \(pct)%" : "Battery \(pct)%")
    }

    private var accessibilityLabel: String {
        var parts = [entry.name, entry.kind.displayName, entry.status.label]
        if let pct = entry.batteryPercent { parts.append("battery \(pct)%") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - ConnectionLogRow

private struct ConnectionLogRow: View {
    let log: PeripheralConnectionLog

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: eventIcon)
                .foregroundStyle(eventColor)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(log.deviceName)
                    .font(.caption)
                    .fontWeight(.medium)
                Text(log.event.description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(log.timestamp.formatted(.dateTime.hour().minute()))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(log.deviceName): \(log.event.description)")
    }

    private var eventIcon: String {
        switch log.event {
        case .connected, .reconnected: return "checkmark.circle"
        case .disconnected:            return "xmark.circle"
        case .reconnecting:            return "arrow.clockwise"
        case .failed:                  return "exclamationmark.triangle"
        }
    }

    private var eventColor: Color {
        switch log.event {
        case .connected, .reconnected: return .green
        case .disconnected:            return .red
        case .reconnecting:            return .orange
        case .failed:                  return .red
        }
    }
}
#endif
