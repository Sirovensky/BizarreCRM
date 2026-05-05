import SwiftUI
import DesignSystem
import Networking
import Core

// MARK: - TimeOffListView
//
// Displays the employee's own time-off requests.
// iPhone: NavigationStack + List.
// iPad: NavigationSplitView — list on left, status detail on right.
// FAB-style "Request Time Off" button with Liquid Glass chrome.

public struct TimeOffListView: View {

    @Bindable var vm: TimeOffViewModel
    @State private var showRequestSheet = false
    @State private var selectedRequest: TimeOffRequest?

    public init(vm: TimeOffViewModel) {
        self.vm = vm
    }

    public var body: some View {
        Group {
            if Platform.isCompact {
                iPhoneLayout
            } else {
                iPadLayout
            }
        }
        .navigationTitle("Time Off")
        .task { await vm.load() }
        .sheet(isPresented: $showRequestSheet) {
            TimeOffRequestSheet(vm: vm) { _ in
                showRequestSheet = false
            }
        }
    }

    // MARK: - iPhone layout

    private var iPhoneLayout: some View {
        ZStack(alignment: .bottomTrailing) {
            List {
                statusPicker
                requestRows
            }
            .refreshable { await vm.load() }
            .overlay { stateOverlay }

            requestButton
                .padding(BrandSpacing.lg)
        }
    }

    // MARK: - iPad layout

    private var iPadLayout: some View {
        NavigationSplitView {
            List(selection: $selectedRequest) {
                statusPicker
                requestRows
            }
            .navigationTitle("Time Off")
            .frame(minWidth: 280, idealWidth: 340)
            .overlay { stateOverlay }
            .refreshable { await vm.load() }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showRequestSheet = true
                    } label: {
                        Label("Request Time Off", systemImage: "plus")
                    }
                    .keyboardShortcut("n", modifiers: .command)
                    .accessibilityLabel("Request time off")
                    .accessibilityIdentifier("timeoff.new")
                }
            }
        } detail: {
            if let request = selectedRequest {
                TimeOffDetailView(request: request)
                    .brandHover()
            } else {
                ContentUnavailableView(
                    "Select a Request",
                    systemImage: "calendar.badge.clock",
                    description: Text("Choose a request from the list")
                )
            }
        }
    }

    // MARK: - Shared subviews

    @ViewBuilder
    private var statusPicker: some View {
        Section {
            Picker("Filter", selection: $vm.statusFilter) {
                Text("All").tag(Optional<TimeOffStatus>.none)
                ForEach(TimeOffStatus.allCases, id: \.self) { s in
                    Text(s.rawValue.capitalized).tag(Optional(s))
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Filter by status")
        }
        .onChange(of: vm.statusFilter) { _, _ in
            Task { await vm.load() }
        }
    }

    @ViewBuilder
    private var requestRows: some View {
        Section("Requests") {
            if vm.requests.isEmpty && vm.loadState == .loaded {
                Text("No time-off requests")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityLabel("No time-off requests found")
            } else {
                ForEach(vm.requests) { request in
                    TimeOffRow(request: request)
                        .brandHover()
                }
            }
        }
    }

    private var requestButton: some View {
        Button {
            showRequestSheet = true
        } label: {
            Label("Request Time Off", systemImage: "plus")
                .font(.brandBodyMedium())
                .padding(.horizontal, BrandSpacing.md)
                .padding(.vertical, BrandSpacing.sm)
        }
        .buttonStyle(.plain)
        .background(Color.bizarreOrange, in: Capsule())
        .foregroundStyle(.white)
        .brandGlass(.regular, in: Capsule(), interactive: true)
        .accessibilityLabel("Request time off")
        .accessibilityIdentifier("timeoff.new")
    }

    // MARK: - State overlay

    @ViewBuilder
    private var stateOverlay: some View {
        switch vm.loadState {
        case .loading:
            ProgressView("Loading requests…")
                .accessibilityLabel("Loading time-off requests")
        case let .failed(msg):
            ContentUnavailableView(
                "Couldn't Load Requests",
                systemImage: "exclamationmark.triangle",
                description: Text(msg)
            )
        default:
            EmptyView()
        }
    }
}

// MARK: - TimeOffRow

private struct TimeOffRow: View {
    let request: TimeOffRequest

    var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            statusIndicator
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(request.kind.displayName)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Text("\(String(request.startDate.prefix(10))) – \(String(request.endDate.prefix(10)))")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .monospacedDigit()
            }
            Spacer()
            statusBadge
        }
        .padding(.vertical, BrandSpacing.xxs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var statusIndicator: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
            .accessibilityHidden(true)
    }

    private var statusBadge: some View {
        Text(request.status.rawValue.capitalized)
            .font(.brandLabelSmall())
            .foregroundStyle(statusColor)
            .padding(.horizontal, BrandSpacing.xs)
            .padding(.vertical, 2)
            .background(statusColor.opacity(0.12), in: Capsule())
    }

    private var statusColor: Color {
        switch request.status {
        case .pending:   return .bizarreOrange
        case .approved:  return .green
        case .denied:    return .bizarreError
        case .cancelled: return .bizarreOnSurfaceMuted
        }
    }

    private var accessibilityLabel: String {
        "\(request.kind.displayName) from \(request.startDate.prefix(10)) to \(request.endDate.prefix(10)). Status: \(request.status.rawValue)."
    }
}

// MARK: - TimeOffDetailView (iPad)

private struct TimeOffDetailView: View {
    let request: TimeOffRequest

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                statusCard
                datesSection
                if let reason = request.reason, !reason.isEmpty {
                    reasonSection(reason)
                }
                if let denial = request.denialReason, !denial.isEmpty {
                    denialSection(denial)
                }
            }
            .padding(BrandSpacing.lg)
        }
        .navigationTitle(request.kind.displayName)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var statusCard: some View {
        HStack {
            Text(request.status.rawValue.capitalized)
                .font(.brandTitleMedium())
                .foregroundStyle(statusColor)
            Spacer()
            Image(systemName: statusIcon)
                .font(.system(size: 28))
                .foregroundStyle(statusColor)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BrandSpacing.lg)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status: \(request.status.rawValue)")
    }

    private var datesSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            detailRow(label: "Type", value: request.kind.displayName)
            detailRow(label: "Start", value: String(request.startDate.prefix(10)))
            detailRow(label: "End", value: String(request.endDate.prefix(10)))
            if let at = request.requestedAt {
                detailRow(label: "Requested", value: String(at.prefix(10)))
            }
            if let at = request.decidedAt {
                detailRow(label: "Decided", value: String(at.prefix(10)))
            }
        }
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
    }

    private func reasonSection(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text("Reason")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityAddTraits(.isHeader)
            Text(reason)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Reason: \(reason)")
    }

    private func denialSection(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text("Denial Reason")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreError)
                .accessibilityAddTraits(.isHeader)
            Text(reason)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Denial reason: \(reason)")
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Spacer()
            Text(value)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    private var statusColor: Color {
        switch request.status {
        case .pending:   return .bizarreOrange
        case .approved:  return .green
        case .denied:    return .bizarreError
        case .cancelled: return .bizarreOnSurfaceMuted
        }
    }

    private var statusIcon: String {
        switch request.status {
        case .pending:   return "clock.badge"
        case .approved:  return "checkmark.circle.fill"
        case .denied:    return "xmark.circle.fill"
        case .cancelled: return "minus.circle"
        }
    }
}
