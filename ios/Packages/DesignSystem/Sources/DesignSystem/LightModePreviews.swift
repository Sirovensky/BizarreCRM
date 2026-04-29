import SwiftUI

// MARK: - §91.9 Light-mode preview stubs
//
// Re-run these previews in light mode to verify colour parity with dark mode.
// Five top surfaces: StalenessIndicator, StatusPill, SyncStatusBadge,
// RailSidebarView (via shim), and the SemanticBadge component.
//
// NOTE: RailSidebarView lives in Core which does not import DesignSystem,
// so this file previews the DesignSystem-owned surfaces only. Rail is
// previewed separately in Core/Rail/RailSidebarView.swift.

#if DEBUG

// MARK: - 1. StalenessIndicator — light mode

#Preview("StalenessIndicator — light") {
    VStack(alignment: .leading, spacing: BrandSpacing.base) {
        Text("Staleness Indicator — light mode")
            .font(.brandCaption1())
            .foregroundStyle(.secondary)
        StalenessIndicator(lastSyncedAt: nil)                              // Never synced
        StalenessIndicator(lastSyncedAt: Date().addingTimeInterval(-30))   // Just now
        StalenessIndicator(lastSyncedAt: Date().addingTimeInterval(-900))  // 15 min ago
        StalenessIndicator(lastSyncedAt: Date().addingTimeInterval(-7_200)) // 2 hr ago (warning)
        StalenessIndicator(lastSyncedAt: Date().addingTimeInterval(-20_000)) // stale
    }
    .padding(BrandSpacing.base)
    .background(Color(.systemBackground))
    .preferredColorScheme(.light)
}

// MARK: - 2. StatusPill — light mode

#Preview("StatusPill — light") {
    VStack(alignment: .leading, spacing: BrandSpacing.base) {
        Text("Status Pills — light mode")
            .font(.brandCaption1())
            .foregroundStyle(.secondary)
        HStack(spacing: BrandSpacing.sm) {
            StatusPill("Intake",         hue: .intake)
            StatusPill("In Progress",    hue: .inProgress)
            StatusPill("Awaiting",       hue: .awaiting)
        }
        HStack(spacing: BrandSpacing.sm) {
            StatusPill("Ready",          hue: .ready)
            StatusPill("Completed",      hue: .completed)
            StatusPill("Archived",       hue: .archived)
        }
    }
    .padding(BrandSpacing.base)
    .background(Color(.systemBackground))
    .preferredColorScheme(.light)
}

// MARK: - 3. SemanticBadge — light mode

#Preview("SemanticBadge — light") {
    VStack(alignment: .leading, spacing: BrandSpacing.base) {
        Text("Semantic Badges — light mode")
            .font(.brandCaption1())
            .foregroundStyle(.secondary)
        HStack(spacing: BrandSpacing.sm) {
            SemanticBadge("Success",  severity: .success)
            SemanticBadge("Warning",  severity: .warning)
            SemanticBadge("Danger",   severity: .danger)
        }
        HStack(spacing: BrandSpacing.sm) {
            SemanticBadge("Info",     severity: .info)
        }
    }
    .padding(BrandSpacing.base)
    .background(Color(.systemBackground))
    .preferredColorScheme(.light)
}

// MARK: - 4. OfflineBanner — light mode

#Preview("OfflineBanner — light") {
    VStack(spacing: 0) {
        Text("Offline Banner — light mode")
            .font(.brandCaption1())
            .foregroundStyle(.secondary)
            .padding(.bottom, BrandSpacing.sm)
        OfflineBanner()
    }
    .padding(BrandSpacing.base)
    .background(Color(.systemBackground))
    .preferredColorScheme(.light)
}

// MARK: - 5. BrandButton variants — light mode

#Preview("BrandButton — light") {
    VStack(spacing: BrandSpacing.sm) {
        Text("Brand Buttons — light mode")
            .font(.brandCaption1())
            .foregroundStyle(.secondary)
        BrandButton("Primary Action",    style: .primary)    { }
        BrandButton("Secondary Action",  style: .secondary)  { }
        BrandButton("Ghost Action",      style: .ghost)       { }
        BrandButton("Destructive",       style: .destructive) { }
    }
    .padding(BrandSpacing.base)
    .background(Color(.systemBackground))
    .preferredColorScheme(.light)
}

#endif
