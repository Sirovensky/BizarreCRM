import SwiftUI

// §53 — Form-field focus-next chain
//
// `FormFocusChain` provides a declarative, type-safe mechanism for advancing
// keyboard focus through a sequence of form fields with the "Next" / "Done"
// return key — matching what UIKit forms have always done, but cleanly in
// SwiftUI.
//
// Usage:
//   enum LoginField: Int, FormFocusField { case email, password }
//
//   struct LoginFormView: View {
//       @StateObject private var chain = FormFocusChain<LoginField>()
//
//       var body: some View {
//           VStack {
//               TextField("Email", text: $email)
//                   .focused(chain.binding, equals: .email)
//                   .submitLabel(.next)
//                   .onSubmit { chain.advance(from: .email) }
//
//               SecureField("Password", text: $password)
//                   .focused(chain.binding, equals: .password)
//                   .submitLabel(.done)
//                   .onSubmit { chain.clear(); login() }
//           }
//           .onAppear { chain.focus(.email) }
//       }
//   }

/// Marker protocol — adopt it with a `RawRepresentable<Int>` enum so the
/// chain can step forward/backward by raw-value arithmetic.
public protocol FormFocusField: Hashable, RawRepresentable<Int>, CaseIterable {}

/// Observable focus chain manager.
///
/// Holds the current focus value and exposes helpers for advancing,
/// retreating, and clearing focus so call sites stay concise.
@MainActor
public final class FormFocusChain<Field: FormFocusField>: ObservableObject {

    // MARK: - Published state

    /// The currently focused field, or `nil` when no field has focus.
    @Published public var focused: Field?

    // MARK: - Lifecycle

    public init(initial: Field? = nil) {
        self.focused = initial
    }

    // MARK: - FocusState binding

    /// Pass to `.focused(_:equals:)` on each field view.
    ///
    /// Because `FocusState.Binding` cannot be held as a property outside a
    /// `View`, call sites should use `chain.focus(_:)` / `chain.advance(from:)`
    /// from within `.onSubmit` and derive their own `@FocusState` bound to
    /// `chain.focused` via `.onChange(of: chain.focused)`.
    ///
    /// The convenience modifier `formFocusChain(_:field:)` wires this automatically.

    // MARK: - Mutation

    /// Move focus to a specific field.
    public func focus(_ field: Field) {
        focused = field
    }

    /// Advance focus to the next field in declaration order.
    ///
    /// When `current` is the last field, focus is cleared (keyboard dismisses).
    public func advance(from current: Field) {
        let all = Array(Field.allCases)
        guard let idx = all.firstIndex(of: current) else { return }
        let next = all.index(after: idx)
        focused = next < all.endIndex ? all[next] : nil
    }

    /// Move focus to the previous field in declaration order.
    public func retreat(from current: Field) {
        let all = Array(Field.allCases)
        guard let idx = all.firstIndex(of: current), idx > all.startIndex else { return }
        focused = all[all.index(before: idx)]
    }

    /// Dismiss the keyboard by clearing focus.
    public func clear() {
        focused = nil
    }
}

// MARK: - View modifier

/// Attaches `FormFocusChain` focus tracking to a field view, handling `.next`
/// submit automatically without boilerplate at the call site.
///
/// Usage:
///   TextField("Email", text: $email)
///       .formFocusChain(chain, field: .email, isLast: false)
///
///   SecureField("Password", text: $password)
///       .formFocusChain(chain, field: .password, isLast: true) {
///           submitForm()
///       }
public struct FormFocusChainModifier<Field: FormFocusField>: ViewModifier {
    @ObservedObject public var chain: FormFocusChain<Field>
    @FocusState private var localFocus: Field?

    public let field: Field
    public let isLast: Bool
    public let onDone: (() -> Void)?

    public func body(content: Content) -> some View {
        content
            .focused($localFocus, equals: field)
            .submitLabel(isLast ? .done : .next)
            .onSubmit {
                if isLast {
                    chain.clear()
                    onDone?()
                } else {
                    chain.advance(from: field)
                }
            }
            // Keep chain.focused and localFocus in sync (two-way).
            .onChange(of: chain.focused) { newValue in
                localFocus = newValue
            }
            .onChange(of: localFocus) { newValue in
                if chain.focused != newValue { chain.focused = newValue }
            }
    }
}

public extension View {
    /// Wire this field into a `FormFocusChain`, handling Next / Done automatically.
    func formFocusChain<Field: FormFocusField>(
        _ chain: FormFocusChain<Field>,
        field: Field,
        isLast: Bool = false,
        onDone: (() -> Void)? = nil
    ) -> some View {
        modifier(FormFocusChainModifier(chain: chain, field: field, isLast: isLast, onDone: onDone))
    }
}
