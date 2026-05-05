import SwiftUI
import Core
import DesignSystem
import Networking

@MainActor
@Observable
final class SegmentListViewModel {
    private(set) var segments: [Segment] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let api: APIClient

    init(api: APIClient) { self.api = api }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let resp = try await api.listSegments()
            segments = resp.segments
        } catch {
            AppLog.ui.error("Segment list load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}

public struct SegmentListView: View {
    @State private var vm: SegmentListViewModel
    @State private var showingCreate = false
    @State private var selectedSegmentId: String? = nil
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
        _vm = State(wrappedValue: SegmentListViewModel(api: api))
    }

    public var body: some View {
        Group {
            if Platform.isCompact { compactLayout } else { regularLayout }
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .sheet(isPresented: $showingCreate, onDismiss: { Task { await vm.load() } }) {
            SegmentEditorView(api: api)
        }
    }

    // MARK: Layouts

    private var compactLayout: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle("Segments")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { newButton }
            .navigationDestination(for: String.self) { id in
                SegmentEditorView(api: api, existingId: id)
            }
        }
    }

    private var regularLayout: some View {
        NavigationSplitView {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle("Segments")
            .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 440)
            .toolbar { newButton }
        } detail: {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                if let id = selectedSegmentId {
                    SegmentEditorView(api: api, existingId: id)
                } else {
                    VStack(spacing: BrandSpacing.md) {
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 52)).foregroundStyle(.bizarreOnSurfaceMuted).accessibilityHidden(true)
                        Text("Select a segment")
                            .font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.segments.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage, vm.segments.isEmpty {
            errorPane(err)
        } else if vm.segments.isEmpty {
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "person.3").font(.system(size: 48)).foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                Text("No segments yet").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(vm.segments) { segment in
                    NavigationLink(value: segment.id) {
                        SegmentRow(segment: segment)
                    }
                    .listRowBackground(Color.bizarreSurface1)
                    #if canImport(UIKit)
                    .hoverEffect(.highlight)
                    #endif
                }
            }
            #if canImport(UIKit)
            .listStyle(.insetGrouped)
            #else
            .listStyle(.inset)
            #endif
            .scrollContentBackground(.hidden)
        }
    }

    private func errorPane(_ msg: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36)).foregroundStyle(.bizarreError).accessibilityHidden(true)
            Text("Couldn't load segments").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
            Text(msg).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted).multilineTextAlignment(.center)
            Button("Try again") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent).tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var newButton: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { showingCreate = true } label: { Image(systemName: "plus") }
                .accessibilityLabel("New segment")
                .accessibilityIdentifier("marketing.segments.new")
                #if canImport(UIKit)
                .keyboardShortcut("N", modifiers: .command)
                #endif
        }
    }
}

// MARK: - Row

private struct SegmentRow: View {
    let segment: Segment

    var body: some View {
        HStack(alignment: .center, spacing: BrandSpacing.md) {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(segment.name)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
                Text(rulesSummary)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let count = segment.cachedCount {
                Text("\(count)")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a11yLabel)
    }

    private var rulesSummary: String {
        let op = segment.rule.op
        let count = segment.rule.rules.count
        return "\(count) rule\(count == 1 ? "" : "s") • \(op)"
    }

    private var a11yLabel: String {
        var parts = [segment.name, rulesSummary]
        if let count = segment.cachedCount { parts.append("\(count) contacts") }
        return parts.joined(separator: ". ")
    }
}
