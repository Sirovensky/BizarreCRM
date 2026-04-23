#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Networking
import Core

/// §6.6 — List of stocktake sessions with status filter.
/// iPhone: full-screen NavigationStack with list.
/// iPad: detail pane content; parent NavigationSplitView is in InventoryListView.
public struct StocktakeListView: View {
    @State private var vm: StocktakeListViewModel
    @State private var showNewSession: Bool = false
    @State private var selectedSessionId: Int64?

    private let api: APIClient
    private let statusOptions: [(label: String, value: String?)] = [
        ("All", nil),
        ("Open", "open"),
        ("Committed", "committed"),
        ("Cancelled", "cancelled"),
    ]

    public init(api: APIClient) {
        self.api = api
        _vm = State(wrappedValue: StocktakeListViewModel(api: api))
    }

    public var body: some View {
        Group {
            if Platform.isCompact {
                iPhoneLayout
            } else {
                iPadLayout
            }
        }
        .navigationTitle("Stocktakes")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showNewSession = true
                } label: {
                    Label("New session", systemImage: "plus")
                }
                .keyboardShortcut("N", modifiers: .command)
                .accessibilityLabel("Start new stocktake session")
            }
            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    ForEach(statusOptions, id: \.label) { opt in
                        Button(opt.label) {
                            vm.statusFilter = opt.value
                            Task { await vm.load() }
                        }
                    }
                } label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("Filter stocktake sessions by status")
            }
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .sheet(isPresented: $showNewSession) {
            StocktakeStartView(api: api)
        }
    }

    // MARK: - iPhone

    private var iPhoneLayout: some View {
        listContent
    }

    // MARK: - iPad: two-column (list + scan detail)

    private var iPadLayout: some View {
        NavigationSplitView {
            listContent
        } detail: {
            if let id = selectedSessionId {
                StocktakeScanView(api: api, sessionId: id)
            } else {
                ContentUnavailableView(
                    "Select a session",
                    systemImage: "barcode.viewfinder",
                    description: Text("Tap a stocktake session to open the count view.")
                )
            }
        }
    }

    // MARK: - Shared list body

    @ViewBuilder
    private var listContent: some View {
        if vm.isLoading && vm.sessions.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage {
            ContentUnavailableView(
                "Error",
                systemImage: "exclamationmark.triangle",
                description: Text(err)
            )
        } else if vm.sessions.isEmpty {
            emptyState
        } else {
            sessionList
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No stocktakes", systemImage: "barcode.viewfinder")
                .accessibilityLabel("No stocktake sessions")
        } description: {
            Text("Start a count session to track physical inventory.")
        } actions: {
            Button("New session") { showNewSession = true }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
                .accessibilityLabel("Start new stocktake session")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
    }

    private var sessionList: some View {
        List(vm.sessions) { session in
            if Platform.isCompact {
                NavigationLink(destination: StocktakeScanView(api: api, sessionId: session.id)) {
                    sessionRow(session)
                }
                .accessibilityLabel(sessionAccessibilityLabel(session))
            } else {
                Button {
                    selectedSessionId = session.id
                } label: {
                    sessionRow(session)
                }
                .buttonStyle(.plain)
                .hoverEffect(.highlight)
                .accessibilityLabel(sessionAccessibilityLabel(session))
                .contextMenu {
                    Button("Open") { selectedSessionId = session.id }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
    }

    private func sessionRow(_ session: StocktakeSession) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            statusIcon(session.status)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(session.name.isEmpty ? "Untitled" : session.name)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                if let location = session.location, !location.isEmpty {
                    Text(location)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                if let openedAt = session.openedAt {
                    Text(openedAt)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }

            Spacer()

            statusBadge(session.status)
        }
        .padding(.vertical, BrandSpacing.xs)
    }

    @ViewBuilder
    private func statusIcon(_ status: String) -> some View {
        switch status {
        case "open":
            Image(systemName: "circle.dashed")
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
        case "committed":
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.bizarreSuccess)
                .accessibilityHidden(true)
        default:
            Image(systemName: "xmark.circle")
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func statusBadge(_ status: String) -> some View {
        let (label, color): (String, Color) = switch status {
        case "open":       ("Open", .bizarreOrange)
        case "committed":  ("Done", .bizarreSuccess)
        default:           ("Cancelled", .bizarreOnSurfaceMuted)
        }
        Text(label)
            .font(.brandLabelSmall())
            .foregroundStyle(color)
            .padding(.horizontal, BrandSpacing.xs)
            .padding(.vertical, BrandSpacing.xxs)
            .brandGlass(.thin, in: Capsule(), tint: color.opacity(0.2))
            .accessibilityLabel("Status: \(label)")
    }

    private func sessionAccessibilityLabel(_ session: StocktakeSession) -> String {
        let name = session.name.isEmpty ? "Untitled" : session.name
        return "\(name), \(session.status)"
    }
}
#endif
