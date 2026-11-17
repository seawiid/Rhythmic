import Foundation

// Presentation logic for the vertical timeline, kept here (pure Foundation) so it can be tested.
// Geometry is continuous in elapsed time: a time-zone change relabels the clock, it never moves
// or resizes a block.

extension Trip {
    /// The zone of the most recently reached place: the origin until the first landing, then each
    /// arrival airport from the exact landing instant until the next landing (through transit and the
    /// following flight). Differs from `zoneID(at:)`, which switches to the destination at takeoff.
    public func clockZoneID(at date: Date) -> String {
        var zone = first.originZoneID
        for s in segments where s.arrival <= date { zone = s.destinationZoneID }
        return zone
    }

    /// Airport code of the most recently reached place (see `clockZoneID(at:)`).
    public func clockAirport(at date: Date) -> String {
        var code = first.origin
        for s in segments where s.arrival <= date { code = s.destination }
        return code
    }

    /// City name for the clock label: the airport's city, or the zone's city if the airport is unknown.
    public func clockCity(at date: Date) -> String {
        Airports.lookup(clockAirport(at: date))?.city ?? TimelineLayout.cityName(clockZoneID(at: date))
    }
}

public enum FlightEventKind: String, Sendable, Hashable { case takeoff, landing }

public struct FlightEvent: Sendable, Hashable, Identifiable {
    public var kind: FlightEventKind
    public var date: Date
    public var segment: FlightSegment
    /// Airport where the event happens and the zone its local time is shown in.
    public var airport: String
    public var zoneID: String
    public var id: String { "\(kind.rawValue)-\(segment.id)" }
}

public struct TimelineDay: Sendable, Hashable, Identifiable {
    /// Position in the plan; unique even if a date repeats (westward across the date line).
    public var index: Int
    public var span: TimeSpan
    /// Local date of the clock zone during this day.
    public var year: Int, month: Int, day: Int
    public var zoneIDAtStart: String
    public var id: Int { index }
}

public struct TimelineLabel: Sendable, Hashable {
    public enum Kind: Sendable, Hashable { case dayStart, hour, event(FlightEventKind) }
    public var kind: Kind
    public var date: Date
    /// Zone used to format the time.
    public var zoneID: String
    /// Location name to show under the time (day start and time-zone changes only).
    public var city: String?
    /// Vertical centre of the time text, in points from the day's top.
    public var y: CGFloat
    /// Top and bottom of the whole label (time + optional city).
    public var top: CGFloat
    public var bottom: CGFloat
}

public struct LaneItem: Sendable, Hashable, Identifiable {
    public var block: PlanBlock
    /// The part of the block drawn in this day (clipped, and trimmed by higher-priority blocks).
    public var span: TimeSpan
    public var id: String { "\(block.id)@\(Int(span.start.timeIntervalSince1970))" }
}

public struct LabelMetrics: Sendable {
    public var timeHeight: CGFloat
    /// Height of the location name under a time; may depend on the name (one or two lines).
    public var cityHeight: @Sendable (String) -> CGFloat
    public var gap: CGFloat
    public init(timeHeight: CGFloat, cityHeight: CGFloat, gap: CGFloat = 2) {
        self.timeHeight = timeHeight; self.cityHeight = { _ in cityHeight }; self.gap = gap
    }
    public init(timeHeight: CGFloat, gap: CGFloat = 2, cityHeight: @escaping @Sendable (String) -> CGFloat) {
        self.timeHeight = timeHeight; self.cityHeight = cityHeight; self.gap = gap
    }
}

public enum TimelineLayout {
    // MARK: Days

    /// Splits the plan horizon at each local midnight of the clock zone. Days are contiguous,
    /// half-open and cover the horizon exactly; a zone change shortens or lengthens a day.
    public static func days(for plan: Plan) -> [TimelineDay] {
        let trip = plan.trip
        var boundaries = Set<Date>([plan.horizon.start, plan.horizon.end])
        // Clock-zone intervals: [start, firstLanding), [landing_i, landing_i+1), ...
        var cuts = [plan.horizon.start] + trip.segments.map(\.arrival).filter { plan.horizon.contains($0) } + [plan.horizon.end]
        cuts = Array(Set(cuts)).sorted()
        for (a, b) in zip(cuts, cuts.dropFirst()) {
            let zone = trip.clockZoneID(at: a)
            var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: zone)!
            var t = a
            while let next = cal.nextDate(after: t, matching: DateComponents(hour: 0, minute: 0, second: 0), matchingPolicy: .nextTime), next < b {
                boundaries.insert(next); t = next
            }
            // A landing that changes the local date starts a new day.
            if a != plan.horizon.start {
                let before = trip.clockZoneID(at: a.addingTimeInterval(-1))
                if localDate(a.addingTimeInterval(-1), before) != localDate(a, zone) { boundaries.insert(a) }
            }
        }
        let sorted = boundaries.sorted()
        return zip(sorted, sorted.dropFirst()).enumerated().map { i, pair in
            let zone = trip.clockZoneID(at: pair.0)
            let d = localDate(pair.0, zone)
            return TimelineDay(index: i, span: TimeSpan(pair.0, pair.1), year: d.0, month: d.1, day: d.2, zoneIDAtStart: zone)
        }
    }

    static func localDate(_ d: Date, _ zone: String) -> (Int, Int, Int) {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: zone)!
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return (c.year!, c.month!, c.day!)
    }

    /// The day containing `date`, if any.
    public static func dayIndex(containing date: Date, in days: [TimelineDay]) -> Int? {
        days.first { $0.span.contains(date) }?.index
    }

    // MARK: Flight events

    /// Every takeoff and landing within the half-open span, so an event exactly at midnight
    /// belongs to the following day only.
    public static func flightEvents(_ trip: Trip, in span: TimeSpan) -> [FlightEvent] {
        trip.segments.flatMap { s in
            [FlightEvent(kind: .takeoff, date: s.departure, segment: s, airport: s.origin, zoneID: s.originZoneID),
             FlightEvent(kind: .landing, date: s.arrival, segment: s, airport: s.destination, zoneID: s.destinationZoneID)]
        }
        .filter { span.contains($0.date) }
        .sorted { $0.date < $1.date }
    }

    // MARK: Lanes

    /// Display priority in the main lane (first wins where blocks overlap).
    static let mainPriority: [BlockKind] = [.sleep, .nap, .prioritizeLight, .reduceLight, .lightHelpful]

    /// Main recommendation lane: sleep, naps and light, clipped to the day and made non-overlapping
    /// by priority, so the column is one continuous sequence of blocks.
    public static func mainLane(_ plan: Plan, in span: TimeSpan) -> [LaneItem] {
        var taken: [TimeSpan] = []
        var out: [LaneItem] = []
        for kind in mainPriority {
            for b in plan.blocks where b.kind == kind {
                guard let clipped = b.span.intersection(span) else { continue }
                for piece in clipped.subtracting(taken) where piece.duration >= 60 {
                    out.append(LaneItem(block: b, span: piece))
                }
                taken.append(clipped)
            }
        }
        return out.sorted { $0.span.start < $1.span.start }
    }

    public static func caffeineLane(_ plan: Plan, in span: TimeSpan) -> [LaneItem] {
        plan.blocks.filter { $0.kind.lane == .caffeine }
            .compactMap { b in b.span.intersection(span).map { LaneItem(block: b, span: $0) } }
            .filter { $0.span.duration >= 60 }
            .sorted { $0.span.start < $1.span.start }
    }

    // MARK: Labels

    /// Time-column labels for a day. Fixed labels (day start, takeoffs, landings) are placed at their
    /// exact instant (pushed down only if two would touch); ordinary hour labels are dropped where they
    /// would crowd them. The city is shown at the day start and wherever the clock zone changes.
    public static func labels(_ plan: Plan, day: TimelineDay, pointsPerHour: CGFloat, metrics m: LabelMetrics) -> [TimelineLabel] {
        let trip = plan.trip
        func y(_ d: Date) -> CGFloat { CGFloat(d.timeIntervalSince(day.span.start) / 3600) * pointsPerHour }
        func make(_ kind: TimelineLabel.Kind, _ d: Date, zone: String, city: String?) -> TimelineLabel {
            let c = y(d)
            return TimelineLabel(kind: kind, date: d, zoneID: zone, city: city, y: c,
                                 top: c - m.timeHeight / 2, bottom: c + m.timeHeight / 2 + (city.map(m.cityHeight) ?? 0))
        }

        var fixed = [make(.dayStart, day.span.start, zone: day.zoneIDAtStart, city: trip.clockCity(at: day.span.start))]
        for e in flightEvents(trip, in: day.span) {
            let changes = e.kind == .landing && trip.clockZoneID(at: e.date.addingTimeInterval(-1)) != e.zoneID
            if e.date == day.span.start {
                // Event exactly at the day start: it replaces the day-start label.
                fixed[0] = make(.event(e.kind), e.date, zone: e.zoneID, city: trip.clockCity(at: e.date))
            } else {
                fixed.append(make(.event(e.kind), e.date, zone: e.zoneID, city: changes ? trip.clockCity(at: e.date) : nil))
            }
        }
        // The day-start label yields to a flight event that would crowd it; the event takes its city,
        // so the exact event time stays beside its icon and the location is still named.
        if fixed.count > 1, fixed[0].kind == .dayStart {
            let first = fixed.dropFirst().min { $0.date < $1.date }!
            if first.top < fixed[0].bottom + m.gap {
                let i = fixed.firstIndex(of: first)!
                let city = first.city ?? fixed[0].city
                fixed[i] = make(first.kind, first.date, zone: first.zoneID, city: city)
                fixed.removeFirst()
            }
        }
        // Push fixed labels apart if they would touch (close connections at narrow spacing).
        var placed: [TimelineLabel] = []
        for var l in fixed.sorted(by: { $0.date < $1.date }) {
            if let prev = placed.last, l.top < prev.bottom + m.gap {
                let shift = prev.bottom + m.gap - l.top
                l.top += shift; l.bottom += shift; l.y += shift
            }
            placed.append(l)
        }

        // Hour labels where they fit.
        let dayHeight = y(day.span.end)
        for t in hourTicks(trip, in: day.span) where t > day.span.start {
            let l = make(.hour, t, zone: trip.clockZoneID(at: t), city: nil)
            guard l.bottom <= dayHeight + m.timeHeight / 2 else { continue }
            if placed.contains(where: { l.top < $0.bottom + m.gap && $0.top < l.bottom + m.gap }) { continue }
            placed.append(l)
        }
        return placed.sorted { $0.y < $1.y }
    }

    /// Instants within the span where the clock-zone time is on the hour (handles DST and
    /// fractional offsets, since it looks for local :00 rather than adding 3600 s).
    public static func hourTicks(_ trip: Trip, in span: TimeSpan) -> [Date] {
        var cuts = [span.start] + trip.segments.map(\.arrival).filter { span.contains($0) } + [span.end]
        cuts = Array(Set(cuts)).sorted()
        var out: [Date] = []
        for (a, b) in zip(cuts, cuts.dropFirst()) {
            var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: trip.clockZoneID(at: a))!
            if cal.component(.minute, from: a) == 0 && cal.component(.second, from: a) == 0 { out.append(a) }
            var t = a
            while let next = cal.nextDate(after: t, matching: DateComponents(minute: 0, second: 0), matchingPolicy: .nextTime), next < b {
                out.append(next); t = next
            }
        }
        return out
    }

    public static func cityName(_ zoneID: String) -> String {
        zoneID.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? zoneID
    }
}
