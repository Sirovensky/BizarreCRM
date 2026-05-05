import SwiftUI
import Observation
import Core
import Networking
import DesignSystem

// MARK: - §3.7 Announcements / What's new
//
// Sticky glass banner above the KPI grid.
// Backend: GET /api/v1/system/announcements?since=<last_seen>
// Tap → full-screen reader sheet.
// "Dismiss" persists last-seen announcement ID in UserDefaults.

private let kLastSeenAnnouncementKey = "dashboard.announcements.lastSeenId"

// MARK: - ViewModel

@MainActor
@Observable
final class AnnouncementsBannerViewModel {
    var announcements: [SystemAnnouncement] = []
    var isLoading = false
    var currentIndex = 0
    var showFullScreen = false

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private var lastSeenId: Int {
        get { UserDefaults.standard.integer(forKey: kLastSeenAnnouncementKey) }
        set { UserDefaults.standard.set(newValue, forKey: kLastSeenAnnouncementKey) }
    }

    init(api: APIClient) {
        self.api = api
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let since = lastSeenId > 0 ? lastSeenId : nil
            let items = try await api.systemAnnouncements(since: since)
            // Show only unseen announcements
            announcements = items.filter { $0.id > lastSeenId }
        } catch {
            AppLog.ui.error("Announcements load failed: \(error.localizedDescription, privacy: .public)")
            announcements = []
        }
    }

    /// Dismiss the current announcement and persist the seen ID.
    func dismissCurrent() {
        guard !announcements.isEmpty else { return }
        let id = announcements[currentIndex].id
        if id > lastSeenId { lastSeenId = id }
        announcements.remove(at: currentIndex)
        if currentIndex >= announcements.count && currentIndex > 0 {
            currentIndex -= 1
        }
    }

    /// Dismiss all announcements.
    func dismissAll() {
        if let maxId = announcements.map(\.id).max() {
            lastSeenId = maxId
        }
        announcements = []
    }
}

// MARK: - View

/// §3.7 — Sticky glass banner shown above KPI grid when there are unseen announcements.
public struct AnnouncementsBanner: View {
    @State private var vm: AnnouncementsBannerViewModel

    public init(api: APIClient) {
        _vm = State(wrappedValue: AnnouncementsBannerViewModel(api: api))
    }

    public var body: some View {
        if !vm.announcements.isEmpty {
            bannerBody
        }
    }

    private var bannerBody: some View {
        let ann = vm.announcements[min(vm.currentIndex, vm.announcements.count - 1)]
        return Button {
            vm.showFullScreen = true
        } label: {
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: "megaphone.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ann.title)
                        .font(.brandTitleSmall())
                        .foregroundStyle(.bizarreOnSurface)
                        .lineLimit(1)
                    Text(ann.body)
                        .font(.brandBodySmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .lineLimit(2)
                }
                Spacer(minLength: BrandSpacing.xs)
                // Multi-announcement page indicator
                if vm.announcements.count > 1 {
                    Text("\(vm.currentIndex + 1)/\(vm.announcements.count)")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                Button {
                    withAnimation { vm.dismissCurrent() }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss announcement")
            }
            .padding(.horizontal, BrandSpacing.md)
            .padding(.vertical, BrandSpacing.sm)
        }
        .buttonStyle(.plain)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.bizarreOrange.opacity(0.25), lineWidth: 0.5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Announcement: \(ann.title). \(ann.body). Tap to read more.")
        .sheet(isPresented: $vm.showFullScreen) {
            AnnouncementsFullSheetView(
                announcements: vm.announcements,
                onDismissAll: { vm.dismissAll() }
            )
        }
        .task { await vm.load() }
        // Swipe left → next announcement (if multiple)
        .gesture(
            DragGesture(minimumDistance: 30, coordinateSpace: .local)
                .onEnded { value in
                    guard vm.announcements.count > 1 else { return }
                    if value.translation.width < -30 {
                        withAnimation {
                            vm.currentIndex = min(vm.currentIndex + 1, vm.announcements.count - 1)
                        }
                    } else if value.translation.width > 30 {
                        withAnimation {
                            vm.currentIndex = max(vm.currentIndex - 1, 0)
                        }
                    }
                }
        )
    }
}

// MARK: - Full-screen sheet

private struct AnnouncementsFullSheetView: View {
    let announcements: [SystemAnnouncement]
    let onDismissAll: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(announcements) { ann in
                VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                    Text(ann.title)
                        .font(.brandTitleMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    Text(ann.body)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .padding(.vertical, BrandSpacing.xs)
                .listRowBackground(Color.bizarreSurface1)
            }
            .navigationTitle("What's New")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Dismiss All") {
                        onDismissAll()
                        dismiss()
                    }
                    .foregroundStyle(.bizarreOrange)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
