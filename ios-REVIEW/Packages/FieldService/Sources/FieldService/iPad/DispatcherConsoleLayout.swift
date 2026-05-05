// §22 DispatcherConsoleLayout — 3-column iPad dispatcher console.
//
// Column 1 (sidebar):   TechRosterSidebar — technicians with real-time status.
// Column 2 (content):   Job list — filterable, multi-selectable job list.
// Column 3 (detail):    Map placeholder pane — shows selected job location.
//
// iPad primary. On iPhone collapses to a single-column NavigationStack.
// Liquid Glass chrome only per §22 constraint.
// Keyboard shortcuts wired via DispatcherKeyboardShortcuts.
// Batch toolbar appears when multiple jobs are selected.

import SwiftUI
import DesignSystem
import Core

// MARK: - DispatcherConsoleLayout

public struct DispatcherConsoleLayout: View {

    @State private var vm: DispatcherConsoleViewModel
    @Environment(\.horizontalSizeClass) private var sizeClass

    public init(vm: DispatcherConsoleViewModel) {
        _vm = State(wrappedValue: vm)
    }

    public var body: some View {
        if sizeClass == .compact {
            compactLayout
        } else {
            iPadLayout
        }
    }

    // MARK: - iPad 3-column layout

    private var iPadLayout: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            TechRosterSidebar(vm: vm)
                .navigationTitle("Technicians")
                .accessibilityLabel("Technician roster sidebar")
        } content: {
            DispatcherJobListPane(vm: vm)
                .navigationTitle("All Jobs")
                .accessibilityLabel("Job list")
        } detail: {
            DispatcherMapPane(vm: vm)
                .accessibilityLabel("Job map detail")
        }
        .navigationSplitViewStyle(.balanced)
        .background(DispatcherKeyboardShortcuts(vm: vm))
    }

    // MARK: - iPhone compact fallback

    private var compactLayout: some View {
        NavigationStack {
            DispatcherJobListPane(vm: vm)
                .navigationTitle("All Jobs")
                .toolbar { compactToolbarItems }
        }
        .background(DispatcherKeyboardShortcuts(vm: vm))
    }

    @ToolbarContentBuilder
    private var compactToolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                vm.showTechRoster.toggle()
            } label: {
                Label("Technicians", systemImage: "person.2")
            }
        }
    }
}
