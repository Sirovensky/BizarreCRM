#if canImport(UIKit) && canImport(PencilKit)
import SwiftUI
import PencilKit
import DesignSystem
import Core

/// Floating glass toolbar for annotation tools.
///
/// - iPad: pinned to right edge (trailing).
/// - iPhone: pinned to bottom.
/// - Liquid Glass chrome (`.brandGlass`) per §30.
/// - Tool buttons: pen / highlighter / marker / eraser.
/// - Tapping active pen/marker opens a thickness slider popover.
/// - Tapping active pen/marker/highlighter opens color palette.
/// - Undo / Redo forwarded to VM.
public struct PencilToolPickerToolbar: View {

    @Bindable var vm: PencilAnnotationViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var showThicknessPopover: Bool = false
    @State private var showColorPopover: Bool = false

    public init(vm: PencilAnnotationViewModel) {
        self.vm = vm
    }

    public var body: some View {
        Group {
            if Platform.isCompact {
                bottomBar
            } else {
                sideBar
            }
        }
    }

    // MARK: - Layouts

    private var bottomBar: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            toolButtons
            Divider().frame(height: 28)
            editingButtons
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .brandGlass(.regular, in: Capsule())
        .padding(.bottom, DesignTokens.Spacing.md)
    }

    private var sideBar: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            toolButtons
            Divider().frame(width: 28)
            editingButtons
        }
        .padding(.vertical, DesignTokens.Spacing.lg)
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xl))
        .padding(.trailing, DesignTokens.Spacing.md)
    }

    // MARK: - Tool row

    @ViewBuilder
    private var toolButtons: some View {
        ForEach(AnnotationTool.allCases, id: \.rawValue) { tool in
            toolButton(for: tool)
        }
    }

    private func toolButton(for tool: AnnotationTool) -> some View {
        let isActive = vm.activeTool == tool
        return Button {
            if isActive && tool != .eraser {
                // Second tap on active drawing tool — show options
                showThicknessPopover = true
            } else {
                withAnimation(reduceMotion ? nil : .snappy(duration: DesignTokens.Motion.snappy)) {
                    vm.activeTool = tool
                }
            }
        } label: {
            VStack(spacing: DesignTokens.Spacing.xxs) {
                Image(systemName: tool.iconName)
                    .font(.system(size: 20, weight: isActive ? .bold : .regular))
                    .foregroundStyle(isActive ? Color.bizarreOrange : Color.primary)
                if dynamicTypeSize <= .xLarge {
                    Text(tool.label)
                        .font(.caption2)
                        .foregroundStyle(isActive ? Color.bizarreOrange : Color.secondary)
                }
            }
            .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("\(tool.label) tool\(isActive ? ", selected" : "")")
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .popover(isPresented: $showThicknessPopover, arrowEdge: Platform.isCompact ? .bottom : .leading) {
            thicknessAndColorPanel
        }
    }

    // MARK: - Editing buttons

    private var editingButtons: some View {
        Group {
            Button {
                // Color opens from this button
                showColorPopover = true
            } label: {
                Circle()
                    .fill(vm.activeColor.swiftUIColor)
                    .frame(width: 24, height: 24)
                    .overlay(Circle().strokeBorder(Color.white, lineWidth: 1.5))
            }
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("Color: \(vm.activeColor.label)")
            .popover(isPresented: $showColorPopover, arrowEdge: Platform.isCompact ? .bottom : .leading) {
                colorPalette
            }

            Button {
                vm.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 18))
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Undo")

            Button {
                vm.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: 18))
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Redo")
        }
    }

    // MARK: - Popovers

    private var thicknessAndColorPanel: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("Thickness")
                .font(.subheadline.bold())
            HStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: "minus")
                Slider(
                    value: $vm.activeThickness,
                    in: 1...20,
                    step: 1
                )
                .accessibilityLabel("Stroke thickness, \(Int(vm.activeThickness)) points")
                Image(systemName: "plus")
            }
            Text("Color")
                .font(.subheadline.bold())
            colorPalette
        }
        .padding(DesignTokens.Spacing.lg)
        .presentationDetents([.height(220)])
    }

    private var colorPalette: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(40), spacing: DesignTokens.Spacing.sm), count: 4),
            spacing: DesignTokens.Spacing.sm
        ) {
            ForEach(AnnotationPresetColor.allCases, id: \.label) { preset in
                Button {
                    vm.activeColor = preset
                    showColorPopover = false
                } label: {
                    Circle()
                        .fill(preset.swiftUIColor)
                        .frame(width: 36, height: 36)
                        .overlay {
                            if vm.activeColor.label == preset.label {
                                Circle().strokeBorder(Color.white, lineWidth: 2.5)
                                    .overlay(
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.white)
                                            .font(.caption.bold())
                                    )
                            }
                        }
                }
                .accessibilityLabel("\(preset.label) color\(vm.activeColor.label == preset.label ? ", selected" : "")")
            }
        }
        .padding(DesignTokens.Spacing.md)
    }
}

#endif
