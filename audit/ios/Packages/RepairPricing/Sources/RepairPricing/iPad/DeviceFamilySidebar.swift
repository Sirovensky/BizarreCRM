import SwiftUI
import Core
import DesignSystem

// MARK: - §22 Device Family Sidebar

/// Sidebar column listing the five device families used in §22 three-column layout.
///
/// Renders an "All" row plus one row per `DeviceFamily` case. Tapping a row
/// sets `selectedFamily`; tapping again deselects (→ nil). The badge count shows
/// how many templates belong to each family.
///
/// Liquid Glass is applied to the navigation bar only (per design token rules).
/// Row backgrounds use `bizarreSurface1` — content, not chrome.
public struct DeviceFamilySidebar: View {

    @Binding public var selectedFamily: DeviceFamily?
    public let templateCountsByFamily: [DeviceFamily: Int]

    public init(
        selectedFamily: Binding<DeviceFamily?>,
        templateCountsByFamily: [DeviceFamily: Int]
    ) {
        _selectedFamily = selectedFamily
        self.templateCountsByFamily = templateCountsByFamily
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            List {
                allRow
                Section("Families") {
                    ForEach(DeviceFamily.allCases) { family in
                        FamilyRow(
                            family: family,
                            isSelected: selectedFamily == family,
                            count: templateCountsByFamily[family] ?? 0
                        ) {
                            selectedFamily = (selectedFamily == family) ? nil : family
                        }
                        .listRowBackground(Color.bizarreSurface1)
                        #if canImport(UIKit)
                        .hoverEffect(.highlight)
                        #endif
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: - "All" row

    private var allRow: some View {
        Section {
            Button {
                selectedFamily = nil
            } label: {
                HStack(spacing: BrandSpacing.md) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(selectedFamily == nil ? Color.bizarreOrange : Color.bizarreSurface2)
                            .frame(width: 32, height: 32)
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(selectedFamily == nil ? Color.bizarreOnOrange : Color.bizarreOnSurface)
                    }
                    .accessibilityHidden(true)
                    Text("All Devices")
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                    Spacer()
                    let total = templateCountsByFamily.values.reduce(0, +)
                    if total > 0 {
                        Text("\(total)")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .monospacedDigit()
                    }
                }
                .padding(.vertical, BrandSpacing.xs)
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.bizarreSurface1)
            .accessibilityLabel("All Devices\(selectedFamily == nil ? ", selected" : "")")
            .accessibilityAddTraits(selectedFamily == nil ? [.isSelected] : [])
            #if canImport(UIKit)
            .hoverEffect(.highlight)
            #endif
        }
    }
}

// MARK: - Family row

private struct FamilyRow: View {
    let family: DeviceFamily
    let isSelected: Bool
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: BrandSpacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? Color.bizarreOrange : Color.bizarreSurface2)
                        .frame(width: 32, height: 32)
                    Image(systemName: family.systemImageName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(isSelected ? Color.bizarreOnOrange : Color.bizarreOnSurface)
                }
                .accessibilityHidden(true)
                Text(family.displayName)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .monospacedDigit()
                }
            }
            .padding(.vertical, BrandSpacing.xs)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(family.displayName)\(isSelected ? ", selected" : "")")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - DeviceFamily enum

/// The five canonical device families shown in the §22 sidebar.
public enum DeviceFamily: String, CaseIterable, Identifiable, Sendable, Hashable {
    case iphone  = "iPhone"
    case ipad    = "iPad"
    case mac     = "Mac"
    case android = "Android"
    case other   = "Other"

    public var id: String { rawValue }

    public var displayName: String { rawValue }

    public var systemImageName: String {
        switch self {
        case .iphone:  return "iphone.gen3"
        case .ipad:    return "ipad"
        case .mac:     return "laptopcomputer"
        case .android: return "phone"
        case .other:   return "wrench.and.screwdriver"
        }
    }

    /// Map a free-form server `device_category` string to a `DeviceFamily`.
    /// Uses case-insensitive prefix/contains matching so "Apple iPhone" → .iphone.
    public static func from(string: String?) -> DeviceFamily {
        guard let s = string?.lowercased() else { return .other }
        if s.contains("iphone") || s == "apple" { return .iphone }
        if s.contains("ipad")   { return .ipad }
        if s.contains("mac")    { return .mac }
        if s.contains("android") || s.contains("samsung") || s.contains("google") || s.contains("pixel") {
            return .android
        }
        return .other
    }
}
