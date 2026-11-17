import Foundation

public enum SourceKind: String, Codable, Sendable, CaseIterable {
    case googleCalendar, tripItFeed, manual, sample
}

/// Where a segment came from. A segment merged from several sources keeps all refs.
public struct SourceRef: Codable, Hashable, Sendable {
    public var kind: SourceKind
    /// Source-specific identifier (Google event id, ICS UID, manual UUID…).
    public var externalID: String
    /// Source's own last-modified time if it provides one.
    public var updatedAt: Date?

    public init(kind: SourceKind, externalID: String, updatedAt: Date? = nil) {
        self.kind = kind; self.externalID = externalID; self.updatedAt = updatedAt
    }
}

public enum SegmentStatus: String, Codable, Sendable { case confirmed, cancelled }

/// A fully resolved, normalized flight segment. Every field the planner needs is present;
/// partially-known segments stay as `ImportedSegment` until the user fills gaps.
public struct FlightSegment: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var carrierCode: String?
    public var flightNumber: String?
    public var origin: String            // IATA
    public var destination: String       // IATA
    public var originZoneID: String      // IANA
    public var destinationZoneID: String // IANA
    public var departure: Date
    public var arrival: Date
    public var status: SegmentStatus
    public var sources: [SourceRef]

    public init(id: String, carrierCode: String? = nil, flightNumber: String? = nil,
                origin: String, destination: String, originZoneID: String, destinationZoneID: String,
                departure: Date, arrival: Date, status: SegmentStatus = .confirmed, sources: [SourceRef]) {
        self.id = id; self.carrierCode = carrierCode; self.flightNumber = flightNumber
        self.origin = origin; self.destination = destination
        self.originZoneID = originZoneID; self.destinationZoneID = destinationZoneID
        self.departure = departure; self.arrival = arrival; self.status = status; self.sources = sources
    }

    public var span: TimeSpan { TimeSpan(departure, arrival) }
    public var displayFlight: String {
        [carrierCode, flightNumber].compactMap { $0 }.joined(separator: " ").ifEmpty("\(origin)–\(destination)")
    }
}

/// A raw, possibly incomplete segment as produced by an importer.
/// Times may come as absolute instants (RFC 3339 with offset / UTC) or as local wall times.
public struct ImportedSegment: Codable, Hashable, Sendable {
    public enum TimeValue: Codable, Hashable, Sendable {
        case instant(Date)
        case local(LocalDateTime, zoneID: String?)
    }

    public var source: SourceRef
    public var carrierCode: String?
    public var flightNumber: String?
    public var origin: String?
    public var destination: String?
    public var departure: TimeValue?
    public var arrival: TimeValue?
    public var originZoneID: String?
    public var destinationZoneID: String?
    public var cancelled: Bool
    /// Original text, kept for the review screen so nothing is invented.
    public var rawSummary: String?

    public init(source: SourceRef, carrierCode: String? = nil, flightNumber: String? = nil,
                origin: String? = nil, destination: String? = nil,
                departure: TimeValue? = nil, arrival: TimeValue? = nil,
                originZoneID: String? = nil, destinationZoneID: String? = nil,
                cancelled: Bool = false, rawSummary: String? = nil) {
        self.source = source; self.carrierCode = carrierCode; self.flightNumber = flightNumber
        self.origin = origin; self.destination = destination
        self.departure = departure; self.arrival = arrival
        self.originZoneID = originZoneID; self.destinationZoneID = destinationZoneID
        self.cancelled = cancelled; self.rawSummary = rawSummary
    }
}

/// A group of connecting segments forming one journey.
public struct Trip: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var segments: [FlightSegment]

    public init(id: String, segments: [FlightSegment]) {
        self.id = id
        self.segments = segments.sorted { $0.departure < $1.departure }
    }

    public var first: FlightSegment { segments[0] }
    public var last: FlightSegment { segments[segments.count - 1] }
    public var departure: Date { first.departure }
    public var arrival: Date { last.arrival }
    public var originZoneID: String { first.originZoneID }
    public var destinationZoneID: String { last.destinationZoneID }
    /// "WDH → ADD → SIN". A ground transfer between airports shows both: "WDH → JNB / SIN → ADD".
    public var title: String {
        var out = first.origin
        for (i, s) in segments.enumerated() {
            if i > 0, s.origin != segments[i - 1].destination { out += " / \(s.origin)" }
            out += " → \(s.destination)"
        }
        return out
    }

    /// Destination's UTC offset minus the departure airport's, at arrival, wrapped to (−12, 12].
    public var zoneChangeHours: Double {
        var d = Zone.offsetHours(destinationZoneID, at: arrival) - Zone.offsetHours(originZoneID, at: arrival)
        while d > 12 { d -= 24 }
        while d <= -12 { d += 24 }
        return d
    }

    /// Hours of time change within which a trip isn't worth shifting your body clock for.
    public static let noShiftWindowHours = 3.0

    /// False when the destination is within ±3 h of where the trip departs (e.g. Singapore → Kuala Lumpur).
    public var needsShift: Bool { abs(zoneChangeHours) > Self.noShiftWindowHours }

    /// Stable fingerprint of plan-relevant facts; a change means the plan must be regenerated.
    public var fingerprint: String {
        segments.map { "\($0.origin)\($0.destination)\(Int($0.departure.timeIntervalSince1970))\(Int($0.arrival.timeIntervalSince1970))\($0.originZoneID)\($0.destinationZoneID)" }
            .joined(separator: "|")
    }

    /// IANA zone the traveller is "in" at an instant: origin before departure,
    /// destination zone while airborne (watch set to destination), transit airport between legs.
    public func zoneID(at date: Date) -> String {
        if date < first.departure { return first.originZoneID }
        for (i, s) in segments.enumerated() {
            if date < s.arrival { return s.destinationZoneID }
            if i + 1 < segments.count, date < segments[i + 1].departure { return s.destinationZoneID }
        }
        return last.destinationZoneID
    }

    public func segment(airborneAt date: Date) -> FlightSegment? {
        segments.first { $0.span.contains(date) }
    }
}

extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
