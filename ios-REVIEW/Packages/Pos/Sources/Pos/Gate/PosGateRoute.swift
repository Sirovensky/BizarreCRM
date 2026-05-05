/// PosGateRoute.swift
/// Agent B — Customer Gate (Frame 1)
///
/// Enum-based exit destinations out of the customer gate.
/// Parent router subscribes via `onRouteSelected` closure.

// MARK: - Route

/// The three exit destinations the gate can produce, plus
/// a pickup-ticket shortcut that bypasses catalog entry.
public enum PosGateRoute: Sendable, Equatable {
    /// An existing customer was selected.
    case existing(Int64)
    /// Cashier wants to create a new customer inline.
    case createNew
    /// Walk-in — no customer record attached.
    case walkIn
    /// Open a ready-for-pickup ticket directly.
    case openPickup(Int64)
}
