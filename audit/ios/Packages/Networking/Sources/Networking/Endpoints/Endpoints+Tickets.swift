import Foundation

// §1.1 — Typed endpoint namespaces for the Tickets domain.
//
// Centralises every path string used by `APIClient+Tickets.swift` so callers
// no longer hand-write `/api/v1/tickets/...` literals. This is the first
// domain to migrate per the ActionPlan §1.1 bullet — other domains follow in
// later passes.
//
// Each factory returns `(path: String, query: [URLQueryItem]?)` so existing
// `APIClient.get/post/patch(...)` call sites can adopt them with minimal
// rewiring (no signature changes on `APIClient`).
//
// GROUNDING: every path here was verified against
//   packages/server/src/routes/tickets.routes.ts
//
// SCOPE: this file covers only the endpoints used by `APIClient+Tickets.swift`.
//        The protocol-based factories in `TypedEndpoints/Endpoints.swift`
//        (`Endpoints.Tickets.list/create/detail/...`) cover the higher-level
//        ticket routes and remain unchanged. The two systems coexist while
//        domains migrate piecewise.
//
// The factories are added as an **extension** on the existing
// `Endpoints.Tickets` enum so the typed-endpoint namespace stays unified.

public extension Endpoints.Tickets {

    /// Path + optional query items used by `APIClient+Tickets.swift` callers.
    ///
    /// Returned as a plain tuple so call sites can pass straight into
    /// `APIClient.get/post/patch(_:query:body:as:)` — no refactor of the
    /// transport layer required.
    typealias Route = (path: String, query: [URLQueryItem]?)

    // MARK: - Photo upload

    /// `POST /api/v1/tickets/:ticketId/photos` — multipart photo upload.
    /// Route: tickets.routes.ts:2431.
    static func photos(ticketId: Int64) -> Route {
        ("/api/v1/tickets/\(ticketId)/photos", nil)
    }

    // MARK: - Warranty lookup

    /// `GET /api/v1/tickets/warranty-lookup` — optional `imei` / `serial` / `phone`.
    /// Route: tickets.routes.ts (GET /tickets/warranty-lookup).
    static func warrantyLookup(
        imei: String? = nil,
        serial: String? = nil,
        phone: String? = nil
    ) -> Route {
        var items: [URLQueryItem] = []
        if let imei,   !imei.isEmpty   { items.append(URLQueryItem(name: "imei",   value: imei)) }
        if let serial, !serial.isEmpty { items.append(URLQueryItem(name: "serial", value: serial)) }
        if let phone,  !phone.isEmpty  { items.append(URLQueryItem(name: "phone",  value: phone)) }
        return ("/api/v1/tickets/warranty-lookup", items.isEmpty ? nil : items)
    }

    // MARK: - Device history

    /// `GET /api/v1/tickets/device-history` — optional `imei` / `serial`.
    /// Route: tickets.routes.ts (GET /tickets/device-history).
    static func deviceHistory(
        imei: String? = nil,
        serial: String? = nil
    ) -> Route {
        var items: [URLQueryItem] = []
        if let imei,   !imei.isEmpty   { items.append(URLQueryItem(name: "imei",   value: imei)) }
        if let serial, !serial.isEmpty { items.append(URLQueryItem(name: "serial", value: serial)) }
        return ("/api/v1/tickets/device-history", items.isEmpty ? nil : items)
    }

    // MARK: - Pin / unpin (PATCH partial update)

    /// `PATCH /api/v1/tickets/:id` — partial update, used here for pin/unpin.
    /// Route: tickets.routes.ts PATCH /tickets/:id.
    ///
    /// Disambiguated from the protocol-style `update(id:)` factory in
    /// `TypedEndpoints/Endpoints.swift` by parameter label.
    static func patchTicket(ticketId: Int64) -> Route {
        ("/api/v1/tickets/\(ticketId)", nil)
    }

    // MARK: - Export CSV

    /// `GET /api/v1/tickets/export` — streams CSV with Content-Disposition: attachment.
    /// Route: tickets.routes.ts:1619.
    ///
    /// Caller appends filter/keyword/sort items derived from
    /// `TicketListFilter` / `TicketSortOrder`. We accept already-built items
    /// because filter/sort enums own their own canonical query shapes.
    static func export(query items: [URLQueryItem]) -> Route {
        ("/api/v1/tickets/export", items.isEmpty ? nil : items)
    }

    // MARK: - Attach to invoice

    /// `POST /api/v1/tickets/:id/attach-invoice` — attach ticket to an existing invoice.
    static func attachInvoice(ticketId: Int64) -> Route {
        ("/api/v1/tickets/\(ticketId)/attach-invoice", nil)
    }

    // MARK: - Transfer

    /// `POST /api/v1/tickets/:id/transfer` — transfer ticket to another location.
    static func transfer(ticketId: Int64) -> Route {
        ("/api/v1/tickets/\(ticketId)/transfer", nil)
    }

    // MARK: - Finalize check-in

    /// `POST /api/v1/tickets/:id/finalize` — transitions checkin draft to open.
    static func finalize(ticketId: Int64) -> Route {
        ("/api/v1/tickets/\(ticketId)/finalize", nil)
    }
}
