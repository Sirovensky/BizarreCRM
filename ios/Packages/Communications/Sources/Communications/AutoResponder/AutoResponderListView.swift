import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - AutoResponderListViewModel

@MainActor
@Observable
public final class AutoResponderListViewModel: Sendable {
    public private(set) var rules: [AutoResponderRule] = []
    public private(set) var isLoading: Bool = false
    public private(set) var errorMessage: String?

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) { self.api = api }

    public func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let resp = try await api.get("/api/v1/sms/auto-responders", as: AutoResponderListResponse.self)
            rules = resp.rules
        } catch {
            AppLog.ui.error("AutoResponder load: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    public func toggle(_ rule: AutoResponderRule) async {
        // Optimistic update
        if let idx = rules.firstIndex(where: { $0.id == rule.id }) {
            let updated = AutoResponderRule(
                id: rule.id, triggers: rule.triggers, reply: rule.reply,
                enabled: !rule.enabled, startTime: rule.startTime, endTime: rule.endTime
            )
            rules[idx] = updated
        }
        do {
            _ = try await api.patch(
                "/api/v1/sms/auto-responders/\(rule.id)",
                body: AutoResponderToggleRequest(enabled: !rule.enabled),
                as: AutoResponderRule.self
            )
        } catch {
            AppLog.ui.error("AutoResponder toggle: \(error.localizedDescription, privacy: .public)")
            await load() // revert optimistic update on failure
        }
    }

    public func delete(_ rule: AutoResponderRule) async {
        rules.removeAll { $0.id == rule.id }
        do {
            try await api.delete("/api/v1/sms/auto-responders/\(rule.id)")
        } catch {
            AppLog.ui.error("AutoResponder delete: \(error.localizedDescription, privacy: .public)")
            await load()
        }
    }
}

// MARK: - AutoResponderListView

/// Admin CRUD list for auto-responder rules.
public struct AutoResponderListView: View {
    @State private var vm: AutoResponderListViewModel
    @State private var showEditor: Bool = false
    @State private var editingRule: AutoResponderRule?

    public init(api: APIClient) {
        _vm = State(wrappedValue: AutoResponderListViewModel(api: api))
    }

    public var body: some View {
        Group {
            if Platform.isCompact { compactLayout } else { regularLayout }
        }
        .task { await vm.load() }
        .sheet(isPresented: $showEditor, onDismiss: { editingRule = nil; Task { await vm.load() } }) {
            AutoResponderEditorSheet(rule: editingRule, api: extractAPI()) { _ in
                showEditor = false
                Task { await vm.load() }
            }
        }
    }

    // MARK: - iPhone

    private var compactLayout: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                listContent
            }
            .navigationTitle("Auto-Responders")
            .toolbar {
                ToolbarItem(placement: .primaryAction) { addButton }
            }
        }
    }

    // MARK: - iPad

    private var regularLayout: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            listContent
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) { addButton }
        }
    }

    // MARK: - Shared

    @ViewBuilder
    private var listContent: some View {
        if vm.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage {
            errorView(err)
        } else if vm.rules.isEmpty {
            emptyView
        } else {
            ruleList
        }
    }

    private var ruleList: some View {
        List {
            ForEach(vm.rules) { rule in
                RuleRow(rule: rule) {
                    editingRule = rule
                    showEditor = true
                } onToggle: {
                    Task { await vm.toggle(rule) }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        Task { await vm.delete(rule) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .listRowBackground(Color.bizarreSurface1)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await vm.load() }
    }

    private var emptyView: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "message.badge.filled.fill")
                .font(.system(size: 48))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("No auto-responders yet")
                .font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
            Text("Create rules to automatically reply to incoming keywords.")
                .font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.xl)
            Button("Add Rule") { showEditor = true }
                .buttonStyle(.borderedProminent).tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ err: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36)).foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Couldn't load auto-responders")
                .font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
            Text(err).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center).padding(.horizontal, BrandSpacing.lg)
            Button("Try again") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent).tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var addButton: some View {
        Button {
            editingRule = nil
            showEditor = true
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel("Add auto-responder")
    }

    private func extractAPI() -> APIClient? { nil } // DI done via vm; nil triggers editor-only mode
}

// MARK: - RuleRow

private struct RuleRow: View {
    let rule: AutoResponderRule
    let onEdit: () -> Void
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: BrandSpacing.md) {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(rule.triggers.joined(separator: ", "))
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
                Text(rule.reply)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .lineLimit(2)
                if rule.startTime != nil {
                    Label("Quiet hours set", systemImage: "moon.fill")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
            Spacer()
            Toggle("", isOn: .constant(rule.enabled))
                .labelsHidden()
                .tint(.bizarreOrange)
                .onChange(of: rule.enabled) { _, _ in onToggle() }
                .accessibilityLabel(rule.enabled ? "Disable rule" : "Enable rule")
        }
        .padding(.vertical, BrandSpacing.xs)
        .contentShape(Rectangle())
        .onTapGesture { onEdit() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rule.triggers.joined(separator: ", ")). \(rule.reply). \(rule.enabled ? "Enabled" : "Disabled")")
        .accessibilityAddTraits(.isButton)
        .contextMenu {
            Button("Edit") { onEdit() }
            Button(rule.enabled ? "Disable" : "Enable") { onToggle() }
        }
#if !os(macOS)
        .hoverEffect(.highlight)
#endif
    }
}

// MARK: - Supporting types

public struct AutoResponderListResponse: Decodable, Sendable {
    public let rules: [AutoResponderRule]
}

private struct AutoResponderToggleRequest: Encodable, Sendable {
    let enabled: Bool
}
