import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - CampaignContextMenuActions

/// Callback container keeping call-sites free of Binding coupling.
/// All callbacks are dispatched on `@MainActor` — `@Sendable` is not required
/// because the struct is only ever created and used on the main actor.
public struct CampaignContextMenuActions {
    public let onEdit:      (Campaign) -> Void
    public let onSendNow:   (Campaign) async -> Void
    public let onPreview:   (Campaign) -> Void
    public let onDuplicate: (Campaign) async -> Void
    public let onArchive:   (Campaign) async -> Void

    public init(
        onEdit:      @escaping (Campaign) -> Void,
        onSendNow:   @escaping (Campaign) async -> Void,
        onPreview:   @escaping (Campaign) -> Void,
        onDuplicate: @escaping (Campaign) async -> Void,
        onArchive:   @escaping (Campaign) async -> Void
    ) {
        self.onEdit      = onEdit
        self.onSendNow   = onSendNow
        self.onPreview   = onPreview
        self.onDuplicate = onDuplicate
        self.onArchive   = onArchive
    }
}

// MARK: - CampaignContextMenu view modifier

/// Attaches a `.contextMenu` to any view with the five standard campaign actions.
/// Wire `onSendNow` to `api.runCampaignNow(id:)` (POST /campaigns/:id/run-now).
public struct CampaignContextMenuModifier: ViewModifier {
    let campaign: Campaign
    let actions: CampaignContextMenuActions

    public func body(content: Content) -> some View {
        content.contextMenu {
            // Edit
            Button {
                actions.onEdit(campaign)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .accessibilityLabel("Edit \(campaign.name)")
            .accessibilityIdentifier("marketing.campaign.contextMenu.edit")

            // Send Now — wired to POST /campaigns/:id/run-now
            Button {
                let c = campaign
                Task { await actions.onSendNow(c) }
            } label: {
                Label("Send Now", systemImage: "bolt.fill")
            }
            .disabled(campaign.status == .archived)
            .accessibilityLabel("Send \(campaign.name) now")
            .accessibilityIdentifier("marketing.campaign.contextMenu.sendNow")

            // Preview
            Button {
                actions.onPreview(campaign)
            } label: {
                Label("Preview", systemImage: "eye.fill")
            }
            .accessibilityLabel("Preview \(campaign.name)")
            .accessibilityIdentifier("marketing.campaign.contextMenu.preview")

            Divider()

            // Duplicate
            Button {
                let c = campaign
                Task { await actions.onDuplicate(c) }
            } label: {
                Label("Duplicate", systemImage: "doc.on.doc.fill")
            }
            .accessibilityLabel("Duplicate \(campaign.name)")
            .accessibilityIdentifier("marketing.campaign.contextMenu.duplicate")

            // Archive (destructive-ish — uses orange tint in HIG)
            Button(role: .destructive) {
                let c = campaign
                Task { await actions.onArchive(c) }
            } label: {
                Label("Archive", systemImage: "archivebox.fill")
            }
            .disabled(campaign.status == .archived)
            .accessibilityLabel("Archive \(campaign.name)")
            .accessibilityIdentifier("marketing.campaign.contextMenu.archive")
        }
    }
}

public extension View {
    /// Attach the standard campaign context menu to any view.
    func campaignContextMenu(
        _ campaign: Campaign,
        actions: CampaignContextMenuActions
    ) -> some View {
        modifier(CampaignContextMenuModifier(campaign: campaign, actions: actions))
    }
}

// MARK: - CampaignContextMenuViewModel

/// Drives the five context-menu actions with real API calls.
@MainActor
@Observable
public final class CampaignContextMenuViewModel {
    public private(set) var isBusy = false
    public private(set) var errorMessage: String?
    public private(set) var duplicatedCampaign: CampaignServerRow?

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    /// POST /campaigns/:id/run-now
    public func sendNow(campaign: Campaign) async {
        guard let rowId = campaign.serverRowId else {
            errorMessage = "Campaign has no server ID"
            return
        }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            _ = try await api.runCampaignNow(id: rowId)
        } catch {
            AppLog.ui.error("Context menu sendNow failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    /// PATCH /campaigns/:id  — status → "archived"
    public func archive(campaign: Campaign) async {
        guard let rowId = campaign.serverRowId else {
            errorMessage = "Campaign has no server ID"
            return
        }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            _ = try await api.patchCampaignServer(id: rowId, PatchCampaignServerRequest(status: "archived"))
        } catch {
            AppLog.ui.error("Context menu archive failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    /// POST /campaigns (creates a copy named "Copy of …")
    public func duplicate(campaign: Campaign) async {
        isBusy = true
        errorMessage = nil
        duplicatedCampaign = nil
        defer { isBusy = false }
        do {
            let body = CreateCampaignServerRequest(
                name: "Copy of \(campaign.name)",
                type: campaign.type.rawValue,
                channel: campaign.channel.rawValue,
                templateBody: campaign.template,
                templateSubject: campaign.templateSubject,
                segmentId: campaign.audienceSegmentId.flatMap { Int($0) },
                triggerRuleJson: nil
            )
            duplicatedCampaign = try await api.createCampaignServer(body)
        } catch {
            AppLog.ui.error("Context menu duplicate failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}
