// Core/Mac/MacFindInPage.swift
//
// `.macFindInPage(…)` SwiftUI ViewModifier — adds an in-page Find bar that
// becomes visible on ⌘F, drives a `query` binding, exposes ↵ next-match and
// ⌘G / ⇧⌘G next/prev shortcuts, and ⎋ Escape to dismiss.
//
// Built on `.onCommand(#selector(NSResponder.performTextFinderAction(_:)))`-
// equivalents available in SwiftUI: `.keyboardShortcut("f", modifiers: .command)`
// for invocation, plus a state-driven overlay for the bar UI.
//
// §23.3 Mac polish — Find in page (⌘F in long scrolling views).
//
// Usage:
// ```swift
// LongTicketsScrollView()
//     .macFindInPage(
//         query: $query,
//         matchCount: matches.count,
//         currentMatchIndex: $currentMatch,
//         onSubmitQuery: { search($0) }
//     )
// ```

import SwiftUI

// MARK: - MacFindInPageModifier

/// Backing modifier for `.macFindInPage(…)`.
///
/// Renders a slim "Find: [____] (3 / 12) ↑ ↓ Done" bar pinned to the top of
/// the wrapped view via `.overlay(alignment: .top)` and toggles its visibility
/// on ⌘F.
public struct MacFindInPageModifier: ViewModifier {

    @Binding public var query: String
    public let matchCount: Int
    @Binding public var currentMatchIndex: Int
    public let onSubmitQuery: (String) -> Void

    @State private var isVisible: Bool = false
    @FocusState private var fieldFocused: Bool

    public init(
        query: Binding<String>,
        matchCount: Int,
        currentMatchIndex: Binding<Int>,
        onSubmitQuery: @escaping (String) -> Void
    ) {
        self._query = query
        self.matchCount = max(0, matchCount)
        self._currentMatchIndex = currentMatchIndex
        self.onSubmitQuery = onSubmitQuery
    }

    public func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if isVisible {
                    findBar
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }
            }
            // ⌘F — toggle bar visibility.
            .onCommand_command_f { toggleVisible() }
            // ⌘G — next match.
            .onCommand_command_g { advance(by: +1) }
            // ⇧⌘G — previous match.
            .onCommand_shift_command_g { advance(by: -1) }
    }

    // MARK: Bar

    @ViewBuilder
    private var findBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Find in page", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($fieldFocused)
                .onSubmit { onSubmitQuery(query) }
                .frame(minWidth: 180, maxWidth: 360)

            Text(Self.matchLabel(current: currentMatchIndex, total: matchCount))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(currentMatchIndex + 1) of \(matchCount) matches")

            Button { advance(by: -1) } label: {
                Image(systemName: "chevron.up")
            }
            .keyboardShortcut("g", modifiers: [.shift, .command])
            .disabled(matchCount == 0)
            .help("Previous match (⇧⌘G)")

            Button { advance(by: +1) } label: {
                Image(systemName: "chevron.down")
            }
            .keyboardShortcut("g", modifiers: .command)
            .disabled(matchCount == 0)
            .help("Next match (⌘G)")

            Button("Done") { hide() }
                .keyboardShortcut(.cancelAction) // ⎋ Escape
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
        )
        .onAppear { fieldFocused = true }
    }

    // MARK: Actions

    private func toggleVisible() {
        isVisible.toggle()
        if isVisible { fieldFocused = true }
    }

    private func hide() {
        isVisible = false
        fieldFocused = false
    }

    private func advance(by delta: Int) {
        guard matchCount > 0 else { return }
        currentMatchIndex = Self.wrap(currentMatchIndex + delta, count: matchCount)
    }

    /// Wraps `index` modulo `count`, treating negatives as wrap-around.
    /// Public for tests.
    public static func wrap(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let m = index % count
        return m < 0 ? m + count : m
    }

    /// Human-readable "n of m" label.  Public for tests.
    public static func matchLabel(current: Int, total: Int) -> String {
        guard total > 0 else { return "0 of 0" }
        return "\(current + 1) of \(total)"
    }
}

// MARK: - Keyboard shortcut helpers

private extension View {
    /// Attaches a hidden ⌘F button that proxies to `action`.
    ///
    /// SwiftUI doesn't expose `.onCommand("f", modifiers: …)` directly, so we
    /// piggy-back on the `Button(action:).keyboardShortcut(…)` pattern hidden
    /// off-screen via `.frame(width: 0, height: 0)` + `.allowsHitTesting(false)`.
    func onCommand_command_f(_ action: @escaping () -> Void) -> some View {
        background(
            Button(action: action) { EmptyView() }
                .keyboardShortcut("f", modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        )
    }

    func onCommand_command_g(_ action: @escaping () -> Void) -> some View {
        background(
            Button(action: action) { EmptyView() }
                .keyboardShortcut("g", modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        )
    }

    func onCommand_shift_command_g(_ action: @escaping () -> Void) -> some View {
        background(
            Button(action: action) { EmptyView() }
                .keyboardShortcut("g", modifiers: [.shift, .command])
                .frame(width: 0, height: 0)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        )
    }
}

// MARK: - View extension

public extension View {
    /// Adds an in-page Find bar on ⌘F with ⌘G / ⇧⌘G next/prev navigation.
    ///
    /// - Parameters:
    ///   - query: Binding to the active search string.
    ///   - matchCount: Number of matches the host has computed.
    ///   - currentMatchIndex: Binding to the highlighted match index.
    ///   - onSubmitQuery: Called when the user presses ↵ in the field.
    func macFindInPage(
        query: Binding<String>,
        matchCount: Int,
        currentMatchIndex: Binding<Int>,
        onSubmitQuery: @escaping (String) -> Void
    ) -> some View {
        modifier(
            MacFindInPageModifier(
                query: query,
                matchCount: matchCount,
                currentMatchIndex: currentMatchIndex,
                onSubmitQuery: onSubmitQuery
            )
        )
    }
}
