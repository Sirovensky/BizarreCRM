import SwiftUI
import Core
import DesignSystem
import Networking

@MainActor
@Observable
final class SegmentPickerViewModel {
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
            AppLog.ui.error("Segment picker load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}

public struct SegmentPickerSheet: View {
    @State private var vm: SegmentPickerViewModel
    @Environment(\.dismiss) private var dismiss
    let onPick: (Segment) -> Void

    public init(api: APIClient, onPick: @escaping (Segment) -> Void) {
        _vm = State(wrappedValue: SegmentPickerViewModel(api: api))
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
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.bizarreError)
                    .accessibilityHidden(true)
                Text(err).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurface)
                    .multilineTextAlignment(.center)
                Button("Retry") { Task { await vm.load() } }
                    .buttonStyle(.borderedProminent).tint(.bizarreOrange)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.segments.isEmpty {
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "person.3").font(.system(size: 40)).foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                Text("No saved segments").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(vm.segments) { segment in
                    Button {
                        onPick(segment)
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                                Text(segment.name)
                                    .font(.brandBodyLarge())
                                    .foregroundStyle(.bizarreOnSurface)
                                if let count = segment.cachedCount {
                                    Text("\(count) contacts")
                                        .font(.brandLabelSmall())
                                        .foregroundStyle(.bizarreOnSurfaceMuted)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                                .accessibilityHidden(true)
                        }
                    }
                    .listRowBackground(Color.bizarreSurface1)
                    .accessibilityLabel("\(segment.name)\(segment.cachedCount.map { ", \($0) contacts" } ?? "")")
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
}
