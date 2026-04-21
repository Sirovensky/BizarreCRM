#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import SwiftUI

/// The logical annotation tool, separate from the underlying `PKTool`
/// so the VM can track it and tests can reason about it without UIKit.
public enum AnnotationTool: String, CaseIterable, Sendable {
    case pen
    case highlighter
    case marker
    case eraser

    // MARK: - PK conversion

    func pkTool(color: UIColor, width: CGFloat) -> PKTool {
        switch self {
        case .pen:
            return PKInkingTool(.pen, color: color, width: width)
        case .highlighter:
            return PKInkingTool(.marker, color: color.withAlphaComponent(0.4), width: width * 2)
        case .marker:
            return PKInkingTool(.marker, color: color, width: width * 1.5)
        case .eraser:
            return PKEraserTool(.vector)
        }
    }

    // MARK: - Display

    public var iconName: String {
        switch self {
        case .pen:         return "pencil"
        case .highlighter: return "highlighter"
        case .marker:      return "paintbrush.fill"
        case .eraser:      return "eraser.fill"
        }
    }

    public var label: String {
        switch self {
        case .pen:         return "Pen"
        case .highlighter: return "Highlighter"
        case .marker:      return "Marker"
        case .eraser:      return "Eraser"
        }
    }
}

// MARK: - Preset colors (§80 tokens reference)

public enum AnnotationPresetColor: CaseIterable, Sendable {
    case orange, teal, magenta, red, green, blue, yellow, black

    public var swiftUIColor: Color {
        switch self {
        case .orange:  return Color(uiColor: .systemOrange)
        case .teal:    return Color(uiColor: .systemTeal)
        case .magenta: return Color(uiColor: .systemPink)
        case .red:     return Color(uiColor: .systemRed)
        case .green:   return Color(uiColor: .systemGreen)
        case .blue:    return Color(uiColor: .systemBlue)
        case .yellow:  return Color(uiColor: .systemYellow)
        case .black:   return Color(uiColor: .label)
        }
    }

    public var uiColor: UIColor {
        switch self {
        case .orange:  return .systemOrange
        case .teal:    return .systemTeal
        case .magenta: return .systemPink
        case .red:     return .systemRed
        case .green:   return .systemGreen
        case .blue:    return .systemBlue
        case .yellow:  return .systemYellow
        case .black:   return .label
        }
    }

    public var label: String {
        switch self {
        case .orange:  return "Orange"
        case .teal:    return "Teal"
        case .magenta: return "Magenta"
        case .red:     return "Red"
        case .green:   return "Green"
        case .blue:    return "Blue"
        case .yellow:  return "Yellow"
        case .black:   return "Black"
        }
    }
}

#endif
