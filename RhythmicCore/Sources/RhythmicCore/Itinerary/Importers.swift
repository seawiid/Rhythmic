import Foundation

/// Common interface for itinerary sources. Implementations that need network/OAuth live in the app.
public protocol ItineraryImporter: Sendable {
    var kind: SourceKind { get }
    func fetch() async throws -> [ImportedSegment]
}

/// Heuristics shared by text-based sources. Deliberately conservative: when a field
/// can't be read confidently it stays nil and the normaliser asks the user.
enum FlightText {
    /// "ET 646", "SQ12", "ET0638"
    static func flightNumber(in text: String) -> (String, String)? {
        guard let m = text.firstMatch(of: /\b([A-Z][A-Z0-9]|[A-Z0-9][A-Z])\s?0*(\d{1,4})\b/) else { return nil }
        return (String(m.1), String(m.2))
    }

    /// "WDH to ADD", "WDH - ADD", "WDH→ADD", "(WDH) … (ADD)"
    static func route(in text: String) -> (String, String)? {
        if let m = text.firstMatch(of: /\b([A-Z]{3})\s*(?:to|-|–|→|>)\s*([A-Z]{3})\b/) { return (String(m.1), String(m.2)) }
        let parens = text.matches(of: /\(([A-Z]{3})\)/).map { String($0.1) }
        if parens.count >= 2 { return (parens[0], parens[1]) }
        return nil
    }

    static func looksLikeFlight(_ text: String) -> Bool {
        text.range(of: "flight", options: .caseInsensitive) != nil || text.contains("✈") || route(in: text) != nil
    }
}

// MARK: - ICS (TripIt private calendar feed, or any iCalendar export)

/// Parses iCalendar text. Built against the RFC 5545 structure, NOT yet validated against a
/// real TripIt feed — the summary/description formats are assumptions until a real sample is tested.
public enum ICSParser {
    public static func segments(from ics: String, kind: SourceKind = .tripItFeed) -> [ImportedSegment] {
        // Unfold continuation lines (RFC 5545 §3.1).
        let unfolded = ics.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n ", with: "").replacingOccurrences(of: "\n\t", with: "")
        var out: [ImportedSegment] = []
        var props: [(name: String, params: [String: String], value: String)]? = nil
        for line in unfolded.split(separator: "\n", omittingEmptySubsequences: true).map(String.init) {
            if line == "BEGIN:VEVENT" { props = []; continue }
            if line == "END:VEVENT" {
                if let p = props, let seg = segment(from: p, kind: kind) { out.append(seg) }
                props = nil; continue
            }
            guard props != nil, let colon = line.firstIndex(of: ":") else { continue }
            let head = line[..<colon].split(separator: ";").map(String.init)
            var params: [String: String] = [:]
            for p in head.dropFirst() {
                let kv = p.split(separator: "=", maxSplits: 1).map(String.init)
                if kv.count == 2 { params[kv[0].uppercased()] = kv[1] }
            }
            props!.append((head[0].uppercased(), params, unescape(String(line[line.index(after: colon)...]))))
        }
        return out
    }

    static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: "\\,", with: ",").replacingOccurrences(of: "\\;", with: ";")
    }

    static func segment(from props: [(name: String, params: [String: String], value: String)], kind: SourceKind) -> ImportedSegment? {
        func first(_ n: String) -> (params: [String: String], value: String)? {
            props.first { $0.name == n }.map { ($0.params, $0.value) }
        }
        let summary = first("SUMMARY")?.value ?? ""
        let text = [summary, first("LOCATION")?.value ?? "", first("DESCRIPTION")?.value ?? ""].joined(separator: "\n")
        guard FlightText.looksLikeFlight(summary) || FlightText.looksLikeFlight(first("LOCATION")?.value ?? "") else { return nil }
        let uid = first("UID")?.value ?? summary
        let updated = (first("LAST-MODIFIED") ?? first("DTSTAMP")).flatMap { parseTime($0.value, $0.params).flatMap { if case .instant(let d) = $0 { d } else { nil } } }
        let route = FlightText.route(in: summary) ?? FlightText.route(in: text)
        let number = FlightText.flightNumber(in: summary)
        return ImportedSegment(
            source: SourceRef(kind: kind, externalID: uid, updatedAt: updated),
            carrierCode: number?.0, flightNumber: number?.1,
            origin: route?.0, destination: route?.1,
            departure: first("DTSTART").flatMap { parseTime($0.value, $0.params) },
            arrival: first("DTEND").flatMap { parseTime($0.value, $0.params) },
            cancelled: first("STATUS")?.value.uppercased() == "CANCELLED",
            rawSummary: summary)
    }

    /// "20261123T123000Z" → instant; "20261123T143000" + TZID → local in that zone; floating → local, zone from airport.
    static func parseTime(_ v: String, _ params: [String: String]) -> ImportedSegment.TimeValue? {
        guard let m = v.firstMatch(of: /^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})(Z?)$/) else { return nil }
        let ldt = LocalDateTime(Int(m.1)!, Int(m.2)!, Int(m.3)!, Int(m.4)!, Int(m.5)!)
        if m.7 == "Z" { return .instant(ldt.date(in: "UTC")) }
        if let tz = params["TZID"], TimeZone(identifier: tz) != nil { return .local(ldt, zoneID: tz) }
        return .local(ldt, zoneID: nil)
    }
}

// MARK: - Google Calendar event resources

/// Parses Google Calendar API v3 Event JSON (events.list `items`). Built against the documented
/// resource shape; the summary/location text of `fromGmail` flight events is NOT guaranteed to
/// contain airports or flight numbers, so missing fields are reported, never inferred.
public enum GoogleCalendarEventParser {
    struct Event: Decodable {
        struct When: Decodable { var dateTime: String?; var date: String?; var timeZone: String? }
        var id: String
        var status: String?
        var eventType: String?
        var summary: String?
        var location: String?
        var description: String?
        var updated: String?
        var start: When?
        var end: When?
    }
    struct Page: Decodable { var items: [Event]? }

    public static func segments(fromEventsListJSON data: Data) throws -> [ImportedSegment] {
        let page = try JSONDecoder().decode(Page.self, from: data)
        return (page.items ?? []).compactMap(segment)
    }

    static func segment(_ e: Event) -> ImportedSegment? {
        let summary = e.summary ?? ""
        let text = [summary, e.location ?? "", e.description ?? ""].joined(separator: "\n")
        guard e.eventType == "fromGmail" ? FlightText.looksLikeFlight(text) : FlightText.looksLikeFlight(summary) else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        func date(_ s: String?) -> Date? { s.flatMap { iso.date(from: $0) ?? isoPlain.date(from: $0) } }
        let route = FlightText.route(in: summary) ?? FlightText.route(in: text)
        let number = FlightText.flightNumber(in: summary) ?? FlightText.flightNumber(in: e.description ?? "")
        return ImportedSegment(
            source: SourceRef(kind: .googleCalendar, externalID: e.id, updatedAt: date(e.updated)),
            carrierCode: number?.0, flightNumber: number?.1,
            origin: route?.0, destination: route?.1,
            departure: date(e.start?.dateTime).map { .instant($0) },   // all-day events have no time → missing
            arrival: date(e.end?.dateTime).map { .instant($0) },
            originZoneID: nil, destinationZoneID: nil,  // event timeZone is the calendar's display zone, not the airport's
            cancelled: e.status == "cancelled",
            rawSummary: summary.isEmpty ? nil : summary)
    }
}

/// Cleans up a pasted calendar-feed link (TripIt or any ICS). Tolerates surrounding spaces, line
/// breaks, quotes or angle brackets, and extra text around the link; converts `webcal://` to `https://`.
public enum FeedLink {
    public enum Problem: Error, Equatable {
        case empty
        case noLink
        case notSecure
    }

    public static func normalize(_ raw: String) -> Result<URL, Problem> {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .failure(.empty) }
        // Find the first link anywhere in the pasted text.
        guard let m = text.firstMatch(of: /(?i)(webcals?|https?):\/\/[^\s"'<>]+/) else { return .failure(.noLink) }
        var s = String(m.0)
        let scheme = String(m.1).lowercased()
        if scheme == "http" { return .failure(.notSecure) }
        s = "https" + s.drop(while: { $0 != ":" })
        guard let url = URL(string: s), let host = url.host, host.contains(".") else { return .failure(.noLink) }
        return .success(url)
    }
}
