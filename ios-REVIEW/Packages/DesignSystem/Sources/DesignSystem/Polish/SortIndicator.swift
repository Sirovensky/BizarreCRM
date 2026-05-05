import SwiftUI

// §22.5 — Sort indicator arrows on column headers.
//
// Tiny chevron next to a column title that flips up/down/none based on sort
// state. Matches the SF Symbol `chevron.up`/`chevron.down` weights used by
// SwiftUI's built-in `Table` for visual consistency.
//
// Usage:
//   HStack(spacing: 4) {
//       Text("Created")
//       SortIndicator(direction: .descending)
//   }
//
// Or as a view extension on a column header label:
//   Text("Total").columnSortable(direction: .ascending)
//
// VoiceOver: announces "ascending" / "descending" / "not sorted" so screen
// reader users get the same signal sighted users do.

public enum SortDirection: String, Equatable, Sendable {
    case ascending
    case descending
    case none

    /// Toggle: ascending → descending → none → ascending.
    public func next() -> SortDirection {
        switch self {
        case .ascending: return .descending
        case .descending: return .none
        case .none: return .ascending
        }
    }
}

public struct SortIndicator: View {
    private let direction: SortDirection

    public init(direction: SortDirection) {
        self.direction = direction
    }

    public var body: some View {
        Group {
            switch direction {
            case .ascending:
                Image(systemName: "chevron.up")
                    .accessibilityLabel("ascending")
            case .descending:
                Image(systemName: "chevron.down")
                    .accessibilityLabel("descending")
            case .none:
                // Reserve space so column titles don't shift when toggling sort.
                Image(systemName: "chevron.up")
                    .opacity(0)
                    .accessibilityHidden(true)
            }
        }
        .font(.caption2.weight(.semibold))
        .imageScale(.small)
        .foregroundStyle(direction == .none ? .secondary : .primary)
    }
}

public extension View {
    /// Append a sort indicator to a column header label.
    func columnSortable(direction: SortDirection) -> some View {
        HStack(spacing: 4) {
            self
            SortIndicator(direction: direction)
        }
        .accessibilityElement(children: .combine)
    }
}
