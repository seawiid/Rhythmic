import Foundation

/// A wall-clock time of day (no date, no zone), e.g. a habitual bedtime.
public struct ClockTime: Codable, Hashable, Sendable, Comparable, CustomStringConvertible {
    public var hour: Int
    public var minute: Int

    public init(_ hour: Int, _ minute: Int = 0) {
        precondition((0..<24).contains(hour) && (0..<60).contains(minute), "invalid clock time")
        self.hour = hour
        self.minute = minute
    }

    public var minutesSinceMidnight: Int { hour * 60 + minute }
    public static func < (a: ClockTime, b: ClockTime) -> Bool { a.minutesSinceMidnight < b.minutesSinceMidnight }
    public var description: String { String(format: "%02d:%02d", hour, minute) }
}

/// A local calendar date + wall-clock time *without* a resolved instant.
/// Must be resolved against an IANA zone, which can be ambiguous (DST fall-back)
/// or nonexistent (DST spring-forward). We never guess silently.
public struct LocalDateTime: Codable, Hashable, Sendable, CustomStringConvertible {
    public var year: Int, month: Int, day: Int, hour: Int, minute: Int

    public init(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) {
        self.year = year; self.month = month; self.day = day; self.hour = hour; self.minute = minute
    }

    public var description: String { String(format: "%04d-%02d-%02d %02d:%02d", year, month, day, hour, minute) }

    public enum Resolution: Equatable, Sendable {
        case unique(Date)
        /// Wall time occurs twice (DST fall-back). Both candidates, earlier first.
        case ambiguous(Date, Date)
        /// Wall time is skipped (DST spring-forward).
        case nonexistent
    }

    /// Resolve against a zone by checking which candidate UTC offsets are self-consistent.
    public func resolve(in zone: TimeZone) -> Resolution {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        guard let naive = utc.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)) else {
            return .nonexistent
        }
        let probeOffsets = Set([-36, -12, 0, 12, 36].map { zone.secondsFromGMT(for: naive.addingTimeInterval(Double($0) * 3600)) })
        let candidates = probeOffsets
            .map { naive.addingTimeInterval(-Double($0)) }
            .filter { candidate in
                zone.secondsFromGMT(for: candidate) == Int(naive.timeIntervalSince(candidate))
            }
        let unique = Array(Set(candidates)).sorted()
        switch unique.count {
        case 0: return .nonexistent
        case 1: return .unique(unique[0])
        default: return .ambiguous(unique[0], unique[unique.count - 1])
        }
    }

    /// Convenience for fixtures where the time is known to be unambiguous.
    public func date(in zoneID: String) -> Date {
        guard let zone = TimeZone(identifier: zoneID), case .unique(let d) = resolve(in: zone) else {
            preconditionFailure("\(self) is not uniquely resolvable in \(zoneID)")
        }
        return d
    }

    public init(_ date: Date, in zone: TimeZone) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        self.init(c.year!, c.month!, c.day!, c.hour!, c.minute!)
    }
}

/// Half-open absolute time interval [start, end).
public struct TimeSpan: Codable, Hashable, Sendable, CustomStringConvertible {
    public var start: Date
    public var end: Date

    public init(_ start: Date, _ end: Date) {
        self.start = start
        self.end = max(start, end)
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }
    public var isEmpty: Bool { end <= start }
    public func contains(_ d: Date) -> Bool { d >= start && d < end }
    public func overlaps(_ o: TimeSpan) -> Bool { start < o.end && o.start < end }

    public func intersection(_ o: TimeSpan) -> TimeSpan? {
        let s = max(start, o.start), e = min(end, o.end)
        return e > s ? TimeSpan(s, e) : nil
    }

    /// This span minus all `holes`, as sorted non-empty pieces.
    public func subtracting(_ holes: [TimeSpan]) -> [TimeSpan] {
        var pieces = [self]
        for h in holes where !h.isEmpty {
            pieces = pieces.flatMap { p -> [TimeSpan] in
                guard p.overlaps(h) else { return [p] }
                var out: [TimeSpan] = []
                if h.start > p.start { out.append(TimeSpan(p.start, h.start)) }
                if h.end < p.end { out.append(TimeSpan(h.end, p.end)) }
                return out
            }
        }
        return pieces.filter { !$0.isEmpty }.sorted { $0.start < $1.start }
    }

    public var description: String { "[\(start.formatted(.iso8601)) – \(end.formatted(.iso8601)))" }
}

extension Date {
    func adding(hours h: Double) -> Date { addingTimeInterval(h * 3600) }
    func adding(minutes m: Double) -> Date { addingTimeInterval(m * 60) }
}

public enum Zone {
    /// Offset from UTC in hours at a given instant (handles DST and fractional zones).
    public static func offsetHours(_ zoneID: String, at date: Date) -> Double {
        Double(TimeZone(identifier: zoneID)?.secondsFromGMT(for: date) ?? 0) / 3600
    }

    /// Absolute instant for a local date (y/m/d) at a clock time in a zone.
    /// For DST gaps we use the later valid instant; for ambiguity the first occurrence.
    /// This is used only for *recommendation* times (not flight times), where a
    /// one-hour DST nudge is acceptable and documented.
    public static func instant(year: Int, month: Int, day: Int, minutesSinceMidnight m: Double, zoneID: String) -> Date {
        let zone = TimeZone(identifier: zoneID)!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let midnight = cal.startOfDay(for: cal.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!)
        // Walk from local midnight using wall-clock arithmetic via components.
        let whole = Int(m.rounded(.down))
        let secs = (m - Double(whole)) * 60
        if let d = cal.date(byAdding: DateComponents(minute: whole), to: midnight, wrappingComponents: false) {
            // Calendar adds absolute minutes; correct to wall-clock if a DST transition happened in between.
            let drift = zone.secondsFromGMT(for: midnight) - zone.secondsFromGMT(for: d)
            return d.addingTimeInterval(Double(drift) + secs)
        }
        return midnight.addingTimeInterval(m * 60)
    }

    /// Local calendar day (y, m, d) for an instant in a zone.
    public static func localDay(_ date: Date, _ zoneID: String) -> (year: Int, month: Int, day: Int) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: zoneID)!
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return (c.year!, c.month!, c.day!)
    }

    /// Start of the local day containing `date`, shifted by `days`.
    public static func startOfLocalDay(_ date: Date, _ zoneID: String, addingDays days: Int = 0) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: zoneID)!
        let s = cal.startOfDay(for: date)
        return cal.date(byAdding: .day, value: days, to: s)!
    }
}
