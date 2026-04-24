// MARK: - Appointments API (append-only)
//
// Ownership: §10 Appointments (iOS)
//
// Confirmed server routes (method → path → response shape):
//   GET    /api/v1/leads/appointments             → { success, data: { appointments, pagination } }
//   POST   /api/v1/leads/appointments             → { success, data: Appointment }
//   PUT    /api/v1/leads/appointments/:id         → { success, data: Appointment }
//   DELETE /api/v1/leads/appointments/:id         → { success, data: { message } }
//
// All implementations live in Endpoints/AppointmentsEndpoints.swift (same module).
// This file is the declared ownership point for §10 Appointments — append new
// appointment endpoint wrappers here as the server adds them.
//
// Calendar-mirror helpers (EventKit write-through) live in the Appointments
// package (CalendarIntegration/). The toggle that gates the write-through is
// CalendarSyncSettings (see Appointments package).

// This file is intentionally left as a documentation/ownership marker.
// The actual API extension methods are in Endpoints/AppointmentsEndpoints.swift
// because the Networking module owns the Appointment model.
// Append new methods to the APIClient extension in AppointmentsEndpoints.swift.
