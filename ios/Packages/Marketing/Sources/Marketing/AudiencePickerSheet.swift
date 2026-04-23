import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - ViewModel

@MainActor
@Observable
final class AudiencePickerViewModel {
    private(set) var segments: [Segment] = []
    private(set) var smsGroups: [SmsGroup] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    var searchText: String = ""

    @ObservationIgnored private let api: APIClient

    init(api: APIClient) { self.api = api }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let segs = api.listSegments()
            async let groups = api.listSmsGroups()
            let (s, g) = try await (segs, groups)
            segments = s.segments
            smsGroups = g
        } catch {
            AppLog.ui.error("AudiencePicker load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    var filteredSegments: [Segment] {
        if searchText.isEmpty { return segments }
        return segments.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var filteredGroups: [SmsGroup] {
        if searchText.isEmpty { return smsGroups }
        return smsGroups.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
}

// MARK: - Sheet

/// Unified audience picker — shows both CRM segments and SMS customer groups.
public struct AudiencePickerSheet: View {
    @State private var vm: AudiencePickerViewModel
    @Environment(\.dismiss) private var dismiss
    let onPick: (AudienceSelection) -> Void

    public init(api: APIClient, onPick: @escaping (AudienceSelection) -> Void) {
        _vm = State(wrappedValue: AudiencePickerViewModel(api: api))
        self.onPick = onPick
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                bodyContent
            }
            .navigationTitle("Choose Audience")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .searchable(text: $vm.searchText, prompt: "Search segments or groups")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await vm.load() }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var bodyContent: some View {
        if vm.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage {
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.bizarreError).accessibilityHidden(true)
                Text(err).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurface)
                    .multilineTextAlignment(.center)
                Button("Retry") { Task { await vm.load() } }
                    .buttonStyle(.borderedProminent).tint(.bizarreOrange)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                // All contacts option
                Section {
                    Button {
                        onPick(.all)
                        dismiss()
                    } label: {
                        HStack {
                            Label("All contacts", systemImage: "person.3.fill")
                                .foregroundStyle(.bizarreOnSurface)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.bizarreOnSurfaceMuted)
                                .accessibilityHidden(true)
                        }
                    }
                    .listRowBackground(Color.bizarreSurface1)
                    .accessibilityLabel("All contacts")
                    #if canImport(UIKit)
                    .hoverEffect(.highlight)
                    #endif
                }

                // CRM Segments
                if !vm.filteredSegments.isEmpty {
                    Section("Customer Segments") {
                        ForEach(vm.filteredSegments) { segment in
                            Button {
                                onPick(.segment(
                                    id: segment.id,
                                    name: segment.name,
                                    count: segment.cachedCount ?? 0
                                ))
                                dismiss()
                            } label: {
                                AudienceRow(
                                    icon: "person.2.crop.square.stack",
                                    title: segment.name,
                                    subtitle: segment.cachedCount.map { "\($0) contacts" },
                                    tag: "Segment"
                                )
                            }
                            .listRowBackground(Color.bizarreSurface1)
                            .accessibilityLabel("\(segment.name), \(segment.cachedCount.map { "\($0) contacts" } ?? "unknown count")")
                            #if canImport(UIKit)
                            .hoverEffect(.highlight)
                            #endif
                        }
                    }
                }

                // SMS Groups
                if !vm.filteredGroups.isEmpty {
                    Section("SMS Groups") {
                        ForEach(vm.filteredGroups) { group in
                            Button {
                                onPick(.smsGroup(
                                    id: group.id,
                                    name: group.name,
                                    count: group.memberCountCache
                                ))
                                dismiss()
                            } label: {
                                AudienceRow(
                                    icon: "message.fill",
                                    title: group.name,
                                    subtitle: "\(group.memberCountCache) members",
                                    tag: group.isDynamicBool ? "Dynamic" : "Static"
                                )
                            }
                            .listRowBackground(Color.bizarreSurface1)
                            .accessibilityLabel("\(group.name), \(group.memberCountCache) members")
                            #if canImport(UIKit)
                            .hoverEffect(.highlight)
                            #endif
                        }
                    }
                }

                if vm.filteredSegments.isEmpty && vm.filteredGroups.isEmpty && !vm.searchText.isEmpty {
                    Section {
                        Text("No results for \"\(vm.searchText)\"")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .listRowBackground(Color.clear)
                    }
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
}

// MARK: - Reusable row

private struct AudienceRow: View {
    let icon: String
    let title: String
    let subtitle: String?
    let tag: String

    var body: some View {
        HStack(spacing: BrandSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(.bizarreOrange)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(title)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
                if let sub = subtitle {
                    Text(sub)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
            Spacer(minLength: 0)
            Text(tag)
                .font(.brandLabelSmall())
                .padding(.horizontal, BrandSpacing.sm)
                .padding(.vertical, 2)
                .foregroundStyle(.bizarreOnSurface)
                .background(Color.bizarreSurface2, in: Capsule())
            Image(systemName: "chevron.right")
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .font(.system(size: 12))
                .accessibilityHidden(true)
        }
        .padding(.vertical, BrandSpacing.xxs)
    }
}
