import Foundation
import SwiftUI

/// A single line in a rendered diff view.
public struct DiffLine: Identifiable, Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case added    // green — present in `after` but not `before` (or changed)
        case removed  // red   — present in `before` but not `after` (or changed)
        case unchanged
    }

    public let id: String      // stable key for ForEach
    public let key: String
    public let value: String
    public let kind: Kind

    public init(id: String, key: String, value: String, kind: Kind) {
        self.id = id
        self.key = key
        self.value = value
        self.kind = kind
    }
}

/// Converts an `AuditDiff` into an ordered list of `DiffLine`s suitable for
/// rendering a before/after diff. Keys present in both snapshots are shown as
/// a removed line (before value) followed by an added line (after value).
/// Keys only in `before` are removed; keys only in `after` are added.
///
/// Tested in `AuditDiffRendererTests`.
public enum AuditDiffRenderer {
    public static func render(_ diff: AuditDiff) -> [DiffLine] {
        let allKeys = Set(diff.before.keys).union(diff.after.keys).sorted()
        var lines: [DiffLine] = []

        for key in allKeys {
            let beforeVal = diff.before[key]
            let afterVal  = diff.after[key]

            switch (beforeVal, afterVal) {
            case (.none, .some(let a)):
                // Added
                lines.append(DiffLine(id: "\(key)+", key: key, value: a.displayString, kind: .added))

            case (.some(let b), .none):
                // Removed
                lines.append(DiffLine(id: "\(key)-", key: key, value: b.displayString, kind: .removed))

            case (.some(let b), .some(let a)):
                if b == a {
                    lines.append(DiffLine(id: "\(key)=", key: key, value: b.displayString, kind: .unchanged))
                } else {
                    lines.append(DiffLine(id: "\(key)-", key: key, value: b.displayString, kind: .removed))
                    lines.append(DiffLine(id: "\(key)+", key: key, value: a.displayString, kind: .added))
                }

            case (.none, .none):
                // Shouldn't happen since key came from the union
                break
            }
        }

        return lines
    }

    /// Colour for a diff kind, following standard diff conventions.
    public static func color(for kind: DiffLine.Kind, colorScheme: ColorScheme = .light) -> Color {
        switch kind {
        case .added:     return colorScheme == .dark ? Color(red: 0.15, green: 0.65, blue: 0.3) : Color(red: 0.1, green: 0.55, blue: 0.25)
        case .removed:   return colorScheme == .dark ? Color(red: 0.85, green: 0.25, blue: 0.25) : Color(red: 0.75, green: 0.15, blue: 0.15)
        case .unchanged: return colorScheme == .dark ? Color(white: 0.6) : Color(white: 0.4)
        }
    }

    /// Background tint for a diff line row.
    public static func backgroundColor(for kind: DiffLine.Kind) -> Color {
        switch kind {
        case .added:     return Color(red: 0.12, green: 0.65, blue: 0.3).opacity(0.08)
        case .removed:   return Color(red: 0.85, green: 0.2, blue: 0.2).opacity(0.08)
        case .unchanged: return Color.clear
        }
    }
}
