import SwiftUI
import DesignSystem

// MARK: - DeadLetterFilter

/// All filter dimensions that the filter bar exposes.
public struct DeadLetterFilter: Equatable, Sendable {
    public var entityKind: String?      // nil = all entities
    public var maxAge: DeadLetterAgeFilter
    public var failureReason: String?   // nil = all reasons (substring match)

    public static let all = DeadLetterFilter(
        entityKind: nil,
        maxAge: .any,
        failureReason: nil
    )

    public var isActive: Bool {
        entityKind != nil || maxAge != .any || failureReason != nil
    }
}

// MARK: - DeadLetterAgeFilter

public enum DeadLetterAgeFilter: String, CaseIterable, Identifiable, Sendable {
    case any      = "Any age"
    case last1h   = "Last 1 h"
    case last24h  = "Last 24 h"
    case last7d   = "Last 7 d"
    case older    = "Older than 7 d"

    public var id: String { rawValue }

    /// Cutoff date — items `movedAt` must be after this to pass the filter.
    /// Returns `nil` for `.any` (no cutoff) and a past date for `.older`.
    public func cutoffDate(relativeTo now: Date = Date()) -> Date? {
        switch self {
        case .any:     return nil
        case .last1h:  return now.addingTimeInterval(-3_600)
        case .last24h: return now.addingTimeInterval(-86_400)
        case .last7d:  return now.addingTimeInterval(-604_800)
        case .older:   return now.addingTimeInterval(-604_800)  // handled via `olderThan`
        }
    }

    /// When true, filter keeps items *older than* 7 days instead of newer.
    public var isOlderThanMode: Bool { self == .older }
}

// MARK: - DeadLetterFilterBar

/// Horizontally scrolling filter strip. Binds to a `DeadLetterFilter`.
///
/// Layout: [Entity chips] [Age picker] [Clear — if active]
/// Glass styling on the bar chrome; content chips use `.brandGlass`.
public struct DeadLetterFilterBar: View {
    @Binding var filter: DeadLetterFilter
    let availableEntities: [String]

    public init(filter: Binding<DeadLetterFilter>, availableEntities: [String]) {
        self._filter = filter
        self.availableEntities = availableEntities
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BrandSpacing.sm) {
                entityChips
                agePicker
                if filter.isActive {
                    clearButton
                }
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.vertical, BrandSpacing.xs)
        }
        .accessibilityLabel("Filters")
    }

    // MARK: - Entity chips

    private var entityChips: some View {
        ForEach(availableEntities, id: \.self) { entity in
            let isSelected = filter.entityKind == entity
            Button {
                filter = DeadLetterFilter(
                    entityKind: isSelected ? nil : entity,
                    maxAge: filter.maxAge,
                    failureReason: filter.failureReason
                )
            } label: {
                Text(entity)
                    .font(.brandLabelSmall())
                    .foregroundStyle(isSelected ? .bizarreOnOrange : .bizarreOnSurface)
            }
            .buttonStyle(.brandGlass)
            .tint(isSelected ? .bizarreOrange : nil)
            .accessibilityLabel("Filter by \(entity)")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }

    // MARK: - Age picker

    private var agePicker: some View {
        Menu {
            ForEach(DeadLetterAgeFilter.allCases) { age in
                Button {
                    filter = DeadLetterFilter(
                        entityKind: filter.entityKind,
                        maxAge: age,
                        failureReason: filter.failureReason
                    )
                } label: {
                    Label(age.rawValue, systemImage: filter.maxAge == age ? "checkmark" : "clock")
                }
            }
        } label: {
            HStack(spacing: BrandSpacing.xs) {
                Image(systemName: "clock")
                    .accessibilityHidden(true)
                Text(filter.maxAge.rawValue)
                    .font(.brandLabelSmall())
            }
            .foregroundStyle(filter.maxAge != .any ? .bizarreOrange : .bizarreOnSurface)
        }
        .buttonStyle(.brandGlass)
        .tint(filter.maxAge != .any ? .bizarreOrange : nil)
        .accessibilityLabel("Age filter: \(filter.maxAge.rawValue)")
    }

    // MARK: - Clear button

    private var clearButton: some View {
        Button {
            filter = .all
        } label: {
            HStack(spacing: BrandSpacing.xs) {
                Image(systemName: "xmark.circle.fill")
                    .accessibilityHidden(true)
                Text("Clear")
                    .font(.brandLabelSmall())
            }
            .foregroundStyle(.bizarreError)
        }
        .buttonStyle(.brandGlassClear)
        .accessibilityLabel("Clear all filters")
    }
}

// MARK: - Filtering helper on Array<DeadLetterItem>

public extension Array where Element == DeadLetterItem {
    /// Returns items matching the given filter.
    func applying(_ filter: DeadLetterFilter, now: Date = Date()) -> [DeadLetterItem] {
        applyingFilter(f: filter, now: now)
    }

    private func applyingFilter(f: DeadLetterFilter, now: Date) -> [DeadLetterItem] {
        self.filter { item in
            // Entity kind
            if let kind = f.entityKind, item.entity != kind { return false }

            // Age
            switch f.maxAge {
            case .any:
                break
            case .older:
                let cutoff = f.maxAge.cutoffDate(relativeTo: now)!
                if item.movedAt >= cutoff { return false }
            default:
                if let cutoff = f.maxAge.cutoffDate(relativeTo: now),
                   item.movedAt < cutoff { return false }
            }

            // Failure reason substring match
            if let reason = f.failureReason, !reason.isEmpty {
                let haystack = (item.lastError ?? "").lowercased()
                if !haystack.contains(reason.lowercased()) { return false }
            }

            return true
        }
    }
}
