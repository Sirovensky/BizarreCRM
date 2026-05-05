import SwiftUI

// §53 — Dirty-state diff helper
//
// `FormDirtyState` tracks whether any field in a form has been changed from
// its original value, producing a Boolean `isDirty` flag and a typed list of
// changed field keys.
//
// Usage:
//   struct CustomerEditView: View {
//       @State private var name = customer.name
//       @State private var email = customer.email
//
//       @StateObject private var dirty = FormDirtyState<CustomerField>()
//
//       var body: some View {
//           Form {
//               TextField("Name", text: $name)
//                   .onChange(of: name) { dirty.mark(.name, changed: $0 != customer.name) }
//               TextField("Email", text: $email)
//                   .onChange(of: email) { dirty.mark(.email, changed: $0 != customer.email) }
//           }
//           .toolbar {
//               if dirty.isDirty {
//                   Button("Save") { save() }
//               }
//           }
//           .interactiveDismissDisabled(dirty.isDirty)   // guard unsaved changes
//       }
//   }

/// A lightweight, type-safe dirty-state tracker for forms.
///
/// `Key` is typically an app-defined enum of field identifiers so the caller
/// can query which fields are dirty and build targeted validation or
/// per-field save logic.
@MainActor
public final class FormDirtyState<Key: Hashable & Sendable>: ObservableObject {

    // MARK: - Published state

    /// `true` when at least one field differs from its original value.
    @Published public private(set) var isDirty: Bool = false

    /// The set of field keys that have changed from their original value.
    @Published public private(set) var dirtyFields: Set<Key> = []

    // MARK: - Mutation

    /// Mark or unmark a field as dirty.
    ///
    /// - Parameters:
    ///   - key:     The field identifier.
    ///   - changed: `true` if the current value differs from the original.
    public func mark(_ key: Key, changed: Bool) {
        if changed {
            dirtyFields.insert(key)
        } else {
            dirtyFields.remove(key)
        }
        isDirty = !dirtyFields.isEmpty
    }

    /// Reset all dirty tracking (call after a successful save or discard).
    public func reset() {
        dirtyFields = []
        isDirty = false
    }

    // MARK: - Convenience

    /// Whether a specific field is dirty.
    public func isFieldDirty(_ key: Key) -> Bool {
        dirtyFields.contains(key)
    }
}

// MARK: - Generic Equatable diff helper (value-based, no enum key needed)

/// Compares two `Equatable` snapshots and returns a list of changed key-paths.
///
/// Useful for view-models that already hold an "original" and "draft" struct
/// and want to enumerate what changed without maintaining per-field state.
///
/// ```swift
/// let changes = formDiff(original: original, draft: draft, keyPaths: [
///     (\Customer.name,  "name"),
///     (\Customer.email, "email"),
///     (\Customer.phone, "phone"),
/// ])
/// // changes == ["name"] if only the name field was edited
/// ```
public func formDiff<T>(
    original: T,
    draft: T,
    keyPaths: [(KeyPath<T, some Equatable>, String)]
) -> [String] {
    keyPaths.compactMap { keyPath, label in
        original[keyPath: keyPath] == draft[keyPath: keyPath] ? nil : label
    }
}
