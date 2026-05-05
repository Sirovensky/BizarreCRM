// §57.4 TechnicianNameChip — compact pill badge showing the assigned
// technician's name on job cards and the dispatcher split view.
//
// Variants:
//   .standard  — icon + name, used in job list rows and detail header.
//   .compact   — initials avatar only, used in map annotation callouts.
//
// A11y: chip is a single element labelled "Assigned to <name>".
// Reduce Motion: no animated appearance; chip renders instantly.

import SwiftUI

// MARK: - TechnicianNameChip

public struct TechnicianNameChip: View {

    // MARK: - Configuration

    public enum Variant {
        /// Icon + full name label.
        case standard
        /// Initials-only circular avatar (≤ 2 characters).
        case compact
    }

    public let techName: String
    public let variant: Variant

    public init(techName: String, variant: Variant = .standard) {
        self.techName = techName
        self.variant = variant
    }

    // MARK: - Body

    public var body: some View {
        switch variant {
        case .standard:
            standardChip
        case .compact:
            compactChip
        }
    }

    // MARK: - Standard

    private var standardChip: some View {
        HStack(spacing: 5) {
            Image(systemName: "person.fill")
                .font(.system(size: 10, weight: .semibold))
                .accessibilityHidden(true)
            Text(techName)
                .font(.system(.caption, design: .default, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(technicianColor, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Assigned to \(techName)")
    }

    // MARK: - Compact

    private var compactChip: some View {
        Text(initials)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(technicianColor, in: Circle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Assigned to \(techName)")
    }

    // MARK: - Helpers

    /// Deterministic hue derived from the tech's name so each technician
    /// always gets the same colour across the app.
    private var technicianColor: Color {
        let hash = techName.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        let hue = Double(abs(hash) % 360) / 360.0
        return Color(hue: hue, saturation: 0.6, brightness: 0.65)
    }

    private var initials: String {
        let words = techName.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        switch words.count {
        case 0:  return "?"
        case 1:  return String(words[0].prefix(2)).uppercased()
        default: return (String(words[0].prefix(1)) + String(words[1].prefix(1))).uppercased()
        }
    }
}

// MARK: - Preview helpers (non-public, compile-time only)

#if DEBUG
private struct TechnicianNameChip_Preview: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 12) {
            TechnicianNameChip(techName: "Jordan Smith")
            TechnicianNameChip(techName: "Jordan Smith", variant: .compact)
            TechnicianNameChip(techName: "Alex Rivera")
        }
        .padding()
    }
}
#endif
