import Foundation

// MARK: - AutoResponderRule

/// Client-side model for an SMS auto-responder rule.
/// The server applies the rule; the client does CRUD.
public struct AutoResponderRule: Identifiable, Sendable, Codable, Hashable {
    public let id: UUID
    /// Keyword list (case-insensitive match in message body).
    public var triggers: [String]
    /// Reply body to send when triggered.
    public var reply: String
    public var enabled: Bool
    /// Quiet-hours start (nil = no time restriction). Hour/minute only; date is ignored.
    public var startTime: DateComponents?
    /// Quiet-hours end (nil = no time restriction). Hour/minute only.
    public var endTime: DateComponents?

    public init(
        id: UUID = UUID(),
        triggers: [String],
        reply: String,
        enabled: Bool,
        startTime: DateComponents? = nil,
        endTime: DateComponents? = nil
    ) {
        self.id = id
        self.triggers = triggers
        self.reply = reply
        self.enabled = enabled
        self.startTime = startTime
        self.endTime = endTime
    }

    // MARK: - Matching

    /// Returns `true` if `message` contains any trigger keyword (case-insensitive)
    /// and the rule is enabled.
    public func matches(message: String) -> Bool {
        guard enabled, !triggers.isEmpty else { return false }
        let lower = message.lowercased()
        return triggers.contains { lower.contains($0.lowercased()) }
    }

    // MARK: - Active time window

    /// Returns `true` when the rule should fire at `date` considering any time window.
    /// If no `startTime`/`endTime` is set the rule is always active.
    public func isActive(at date: Date = Date()) -> Bool {
        guard let start = startTime, let end = endTime,
              let sh = start.hour, let sm = start.minute,
              let eh = end.hour, let em = end.minute else {
            return true // no time restriction
        }
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: date)
        guard let hour = comps.hour, let minute = comps.minute else { return true }

        let now  = hour * 60 + minute
        let s    = sh   * 60 + sm
        let e    = eh   * 60 + em

        return now >= s && now < e
    }

    // MARK: - Validation

    /// Returns a list of validation error strings. Empty array means valid.
    public var validationErrors: [String] {
        var errors: [String] = []
        if triggers.isEmpty {
            errors.append("At least one trigger keyword is required.")
        }
        if reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Reply body cannot be empty.")
        }
        if let start = startTime, let end = endTime,
           let sh = start.hour, let sm = start.minute,
           let eh = end.hour, let em = end.minute {
            let s = sh * 60 + sm
            let e = eh * 60 + em
            if s >= e {
                errors.append("Start time must be before end time.")
            }
        }
        return errors
    }

    public var isValid: Bool { validationErrors.isEmpty }

    // MARK: - Codable (DateComponents workaround)

    enum CodingKeys: String, CodingKey {
        case id, triggers, reply, enabled
        case startTimeHour = "start_hour"
        case startTimeMinute = "start_minute"
        case endTimeHour = "end_hour"
        case endTimeMinute = "end_minute"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id      = try c.decode(UUID.self, forKey: .id)
        triggers = try c.decode([String].self, forKey: .triggers)
        reply   = try c.decode(String.self, forKey: .reply)
        enabled = try c.decode(Bool.self, forKey: .enabled)

        if let sh = try c.decodeIfPresent(Int.self, forKey: .startTimeHour),
           let sm = try c.decodeIfPresent(Int.self, forKey: .startTimeMinute) {
            startTime = DateComponents(hour: sh, minute: sm)
        }
        if let eh = try c.decodeIfPresent(Int.self, forKey: .endTimeHour),
           let em = try c.decodeIfPresent(Int.self, forKey: .endTimeMinute) {
            endTime = DateComponents(hour: eh, minute: em)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,       forKey: .id)
        try c.encode(triggers, forKey: .triggers)
        try c.encode(reply,    forKey: .reply)
        try c.encode(enabled,  forKey: .enabled)
        try c.encodeIfPresent(startTime?.hour,   forKey: .startTimeHour)
        try c.encodeIfPresent(startTime?.minute, forKey: .startTimeMinute)
        try c.encodeIfPresent(endTime?.hour,     forKey: .endTimeHour)
        try c.encodeIfPresent(endTime?.minute,   forKey: .endTimeMinute)
    }
}
