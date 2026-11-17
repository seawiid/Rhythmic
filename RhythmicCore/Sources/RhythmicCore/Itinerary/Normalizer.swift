import Foundation

public struct ItineraryIssue: Codable, Hashable, Sendable, Error {
    public enum Kind: String, Codable, Sendable {
        case missingField, unknownAirport, ambiguousLocalTime, nonexistentLocalTime, conflictingSources, groundTransfer, invalidTimes
    }
    public var kind: Kind
    public var message: String
    /// Source of the affected segment, so the review screen can show the original text.
    public var source: SourceRef?
}

public struct NormalizationResult: Sendable {
    public var trips: [Trip]
    public var cancelled: [FlightSegment]
    /// Segments that couldn't be fully resolved; shown for review, never planned on.
    public var incomplete: [ImportedSegment]
    public var issues: [ItineraryIssue]
}

/// Turns raw imported segments from any number of sources into trips.
/// Never invents missing details: anything unresolved becomes an issue for the user.
public enum ItineraryNormalizer {
    public static let connectionWindowHours = 24.0
    /// Two records are the same flight if route matches and departures are within this window.
    static let duplicateWindow: TimeInterval = 3 * 3600
    static let conflictTolerance: TimeInterval = 15 * 60

    public static func normalize(_ imported: [ImportedSegment]) -> NormalizationResult {
        var issues: [ItineraryIssue] = []
        var incomplete: [ImportedSegment] = []

        // 1. Within one source, the newest version of an event wins (updates).
        var latest: [String: (Int, ImportedSegment)] = [:]
        for (i, seg) in imported.enumerated() {
            let key = "\(seg.source.kind.rawValue)|\(seg.source.externalID)"
            if let (_, existing) = latest[key],
               (existing.source.updatedAt ?? .distantPast) > (seg.source.updatedAt ?? .distantPast) { continue }
            latest[key] = (i, seg)
        }
        let current = latest.values.sorted { $0.0 < $1.0 }.map(\.1)

        // 2. Resolve each record.
        var resolved: [FlightSegment] = []
        for raw in current {
            switch resolve(raw) {
            case .success(let seg): resolved.append(seg)
            case .failure(let issue):
                issues.append(issue)
                if !raw.cancelled { incomplete.append(raw) }
            }
        }

        // 3. De-duplicate across sources.
        var merged: [FlightSegment] = []
        for seg in resolved.sorted(by: { $0.departure < $1.departure }) {
            if let idx = merged.firstIndex(where: { isSameFlight($0, seg) }) {
                let existing = merged[idx]
                if abs(existing.departure.timeIntervalSince(seg.departure)) > conflictTolerance
                    || abs(existing.arrival.timeIntervalSince(seg.arrival)) > conflictTolerance {
                    issues.append(ItineraryIssue(kind: .conflictingSources,
                                                 message: "\(seg.displayFlight) \(seg.origin)→\(seg.destination) has different times in different sources. Using the most recently updated one; please check.",
                                                 source: seg.sources.first))
                }
                merged[idx] = merge(existing, seg)
            } else {
                merged.append(seg)
            }
        }

        let cancelled = merged.filter { $0.status == .cancelled }
        let active = merged.filter { $0.status == .confirmed }.sorted { $0.departure < $1.departure }

        // 4. Group connecting segments into trips.
        var trips: [Trip] = []
        var group: [FlightSegment] = []
        for seg in active {
            if let prev = group.last {
                let gap = seg.departure.timeIntervalSince(prev.arrival)
                if gap >= 0 && gap <= connectionWindowHours * 3600 {
                    if seg.origin != prev.destination {
                        issues.append(ItineraryIssue(kind: .groundTransfer,
                                                     message: "You land at \(prev.destination) but the next flight leaves from \(seg.origin). Treated as one trip with a ground transfer.",
                                                     source: seg.sources.first))
                    }
                    group.append(seg); continue
                }
                if gap < 0 {
                    issues.append(ItineraryIssue(kind: .invalidTimes,
                                                 message: "\(seg.displayFlight) departs before \(prev.displayFlight) lands. Please check both flights.",
                                                 source: seg.sources.first))
                }
                trips.append(Trip(id: group[0].id, segments: group))
            }
            group = [seg]
        }
        if !group.isEmpty { trips.append(Trip(id: group[0].id, segments: group)) }

        return NormalizationResult(trips: trips, cancelled: cancelled, incomplete: incomplete, issues: issues)
    }

    static func isSameFlight(_ a: FlightSegment, _ b: FlightSegment) -> Bool {
        guard a.origin == b.origin, a.destination == b.destination,
              abs(a.departure.timeIntervalSince(b.departure)) <= duplicateWindow else { return false }
        if let fa = a.flightNumber, let fb = b.flightNumber, let ca = a.carrierCode, let cb = b.carrierCode {
            return fa == fb && ca == cb
        }
        return true
    }

    /// Prefer the most recently updated record; a manual edit beats an import on ties.
    static func merge(_ a: FlightSegment, _ b: FlightSegment) -> FlightSegment {
        func rank(_ s: FlightSegment) -> (Date, Int) {
            let newest = s.sources.compactMap(\.updatedAt).max() ?? .distantPast
            let manual = s.sources.contains { $0.kind == .manual } ? 1 : 0
            return (newest, manual)
        }
        var winner = rank(b) > rank(a) ? b : a
        let other = winner == a ? b : a
        winner.carrierCode = winner.carrierCode ?? other.carrierCode
        winner.flightNumber = winner.flightNumber ?? other.flightNumber
        winner.sources = Array(Set(a.sources + b.sources)).sorted { ($0.kind.rawValue, $0.externalID) < ($1.kind.rawValue, $1.externalID) }
        winner.id = a.id   // keep the first-seen id stable so notifications/plans don't churn
        return winner
    }

    static func resolve(_ raw: ImportedSegment) -> Result<FlightSegment, ItineraryIssue> {
        let label = raw.rawSummary ?? "A flight"
        func fail(_ kind: ItineraryIssue.Kind, _ msg: String) -> Result<FlightSegment, ItineraryIssue> {
            .failure(ItineraryIssue(kind: kind, message: msg, source: raw.source))
        }
        guard let origin = raw.origin?.uppercased(), origin.count == 3 else { return fail(.missingField, "\(label): departure airport is missing.") }
        guard let dest = raw.destination?.uppercased(), dest.count == 3 else { return fail(.missingField, "\(label): arrival airport is missing.") }
        guard let oz = raw.originZoneID ?? Airports.lookup(origin)?.zoneID, TimeZone(identifier: oz) != nil else {
            return fail(.unknownAirport, "\(label): time zone for \(origin) is unknown. Please choose it.")
        }
        guard let dz = raw.destinationZoneID ?? Airports.lookup(dest)?.zoneID, TimeZone(identifier: dz) != nil else {
            return fail(.unknownAirport, "\(label): time zone for \(dest) is unknown. Please choose it.")
        }
        func instant(_ v: ImportedSegment.TimeValue?, zone: String, what: String) -> Result<Date, ItineraryIssue> {
            switch v {
            case .none: return .failure(ItineraryIssue(kind: .missingField, message: "\(label): \(what) time is missing.", source: raw.source))
            case .instant(let d): return .success(d)
            case .local(let ldt, let z):
                switch ldt.resolve(in: TimeZone(identifier: z ?? zone)!) {
                case .unique(let d): return .success(d)
                case .ambiguous: return .failure(ItineraryIssue(kind: .ambiguousLocalTime, message: "\(label): \(what) time \(ldt) happens twice because of a clock change. Please confirm which.", source: raw.source))
                case .nonexistent: return .failure(ItineraryIssue(kind: .nonexistentLocalTime, message: "\(label): \(what) time \(ldt) doesn't exist because of a clock change. Please check it.", source: raw.source))
                }
            }
        }
        let dep: Date, arr: Date
        switch instant(raw.departure, zone: oz, what: "departure") { case .success(let d): dep = d; case .failure(let e): return .failure(e) }
        switch instant(raw.arrival, zone: dz, what: "arrival") { case .success(let d): arr = d; case .failure(let e): return .failure(e) }
        guard arr > dep else { return fail(.invalidTimes, "\(label): arrival is before departure. Check the times and time zones.") }
        guard arr.timeIntervalSince(dep) < 22 * 3600 else { return fail(.invalidTimes, "\(label): over 22 h in the air. Please check the times.") }

        let utcDay: String = {
            var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
            let c = cal.dateComponents([.year, .month, .day], from: dep)
            return String(format: "%04d%02d%02d", c.year!, c.month!, c.day!)
        }()
        let id = [raw.carrierCode, raw.flightNumber].compactMap { $0 }.joined() + "-\(origin)\(dest)-\(utcDay)"
        return .success(FlightSegment(id: id, carrierCode: raw.carrierCode, flightNumber: raw.flightNumber,
                                      origin: origin, destination: dest, originZoneID: oz, destinationZoneID: dz,
                                      departure: dep, arrival: arr, status: raw.cancelled ? .cancelled : .confirmed,
                                      sources: [raw.source]))
    }
}

extension ImportedSegment {
    /// Approximate end of the flight (arrival, else departure). A local wall time without a known zone
    /// is read as UTC, so it can be off by up to ±14 h; callers allow for that.
    public var approximateEnd: Date? {
        switch arrival ?? departure {
        case .instant(let d): return d
        case .local(let l, let zone):
            var c = DateComponents(year: l.year, month: l.month, day: l.day, hour: l.hour, minute: l.minute)
            c.timeZone = zone.flatMap(TimeZone.init(identifier:)) ?? TimeZone(identifier: "UTC")
            return Calendar(identifier: .gregorian).date(from: c)
        case nil: return nil
        }
    }
}

extension NormalizationResult {
    /// Only what's still relevant: trips that haven't ended (plus `keepTripID`, so a trip in progress
    /// or the selected plan never disappears), and review items for flights that haven't happened yet.
    /// Feeds such as TripIt include past trips; those are hidden, not deleted.
    public func upcoming(from imported: [ImportedSegment], now: Date, keepTripID: String?) -> NormalizationResult {
        let tripCutoff = now.addingTimeInterval(-24 * 3600)
        // Extra margin for local times with an unknown zone (up to ±14 h).
        let rawCutoff = now.addingTimeInterval(-(24 + 14) * 3600)
        let pastSources = Set(imported.filter { ($0.approximateEnd ?? .distantFuture) < rawCutoff }.map(\.source))
        let keptTrips = trips.filter { $0.arrival >= tripCutoff || $0.id == keepTripID }
        let droppedSources = Set(trips.filter { t in !keptTrips.contains { $0.id == t.id } }.flatMap { $0.segments.flatMap(\.sources) })
        return NormalizationResult(
            trips: keptTrips,
            cancelled: cancelled.filter { $0.arrival >= tripCutoff },
            incomplete: incomplete.filter { !pastSources.contains($0.source) },
            issues: issues.filter { i in i.source.map { !pastSources.contains($0) && !droppedSources.contains($0) } ?? true })
    }
}
