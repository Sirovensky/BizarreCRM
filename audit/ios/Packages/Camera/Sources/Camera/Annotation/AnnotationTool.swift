#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import SwiftUI

/// The logical annotation tool, separate from the underlying `PKTool`
/// so the VM can track it and tests can reason about it without UIKit.
///
/// §17.10 extended tools: arrow, rectangle, oval, textBox are shape overlays
/// rendered outside PencilKit (on the SVG/CoreGraphics compositing layer).
/// The PK canvas is hidden when these are active; a separate `ShapeOverlayCanvas`
/// receives touches.
public enum AnnotationTool: String, CaseIterable, Sendable {
    // MARK: PencilKit-backed (ink) tools
    case pen
    case highlighter
    case marker
    case eraser

    // MARK: Shape overlay tools (rendered on the compositing layer above PK)
    /// Auto-headed arrow with configurable direction.
    case arrow
    /// Axis-aligned rectangle outline.
    case rectangle
    /// Axis-aligned oval outline.
    case oval
    /// Text box: taps place an editable `UITextView` overlay, saved as rasterised text.
    case textBox

    // MARK: - PK conversion

    /// Whether this tool operates within PencilKit (ink strokes).
    /// Shape overlay tools return `false` — the PK canvas is deactivated.
    public var isPencilKitTool: Bool {
        switch self {
        case .pen, .highlighter, .marker, .eraser: return true
        case .arrow, .rectangle, .oval, .textBox:  return false
        }
    }

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
        // Shape tools do not map to a PKTool — caller must check `isPencilKitTool`.
        case .arrow, .rectangle, .oval, .textBox:
            return PKInkingTool(.pen, color: color, width: width)
        }
    }

    // MARK: - Display

    public var iconName: String {
        switch self {
        case .pen:         return "pencil"
        case .highlighter: return "highlighter"
        case .marker:      return "paintbrush.fill"
        case .eraser:      return "eraser.fill"
        case .arrow:       return "arrow.up.right"
        case .rectangle:   return "rectangle"
        case .oval:        return "oval"
        case .textBox:     return "textformat"
        }
    }

    public var label: String {
        switch self {
        case .pen:         return "Pen"
        case .highlighter: return "Highlighter"
        case .marker:      return "Marker"
        case .eraser:      return "Eraser"
        case .arrow:       return "Arrow"
        case .rectangle:   return "Rectangle"
        case .oval:        return "Oval"
        case .textBox:     return "Text"
        }
    }
}

// MARK: - Preset colors (§80 tokens reference)
//
// §17.10: "Palette: swatches as glass chips; tenant brand color auto-added"
// Ten built-in presets + custom (via UIColorPickerViewController).

public enum AnnotationPresetColor: CaseIterable, Sendable {
    case orange, teal, magenta, red, green, blue, yellow, black, white, purple

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
        case .white:   return Color(uiColor: .white)
        case .purple:  return Color(uiColor: .systemPurple)
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
        case .white:   return .white
        case .purple:  return .systemPurple
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
        case .white:   return "White"
        case .purple:  return "Purple"
        }
    }
}

#endif
