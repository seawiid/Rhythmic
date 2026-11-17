import Foundation

/// One scheduled leg returned by a flight-number lookup. Built only from what the provider returns:
/// a leg missing airports, times or a resolvable time zone is dropped, never completed by guessing.
public struct FlightOption: Hashable, Sendable, Identifiable {
    public var flightNumber: String          // as returned, e.g. "ET 646"
    public var carrierCode: String?
    public var number: String?
    public var airlineName: String?
    public var origin: String                // IATA
    public var destination: String           // IATA
    public var originName: String?
    public var destinationName: String?
    public var originZoneID: String
    public var destinationZoneID: String
    public var departure: Date               // scheduled, absolute
    public var arrival: Date                 // scheduled, absolute
    public var isCodeshare: Bool
    public var status: String?

    public var id: String { "\(flightNumber)-\(origin)\(destination)-\(Int(departure.timeIntervalSince1970))" }

    /// As an imported record, so it goes through the same normaliser as every other source.
    public func importedSegment(externalID: String, fetchedAt: Date) -> ImportedSegment {
        ImportedSegment(source: SourceRef(kind: .manual, externalID: externalID, updatedAt: fetchedAt),
                        carrierCode: carrierCode, flightNumber: number,
                        origin: origin, destination: destination,
                        departure: .instant(departure), arrival: .instant(arrival),
                        originZoneID: originZoneID, destinationZoneID: destinationZoneID,
                        rawSummary: "\(flightNumber) \(origin) to \(destination) (looked up)")
    }
}

/// "ET646", "et 646", "9W 123" → ("ET", "646"). Returns nil for anything else.
public enum FlightNumberParser {
    public static func parse(_ s: String) -> (carrier: String, number: String)? {
        let t = s.uppercased().replacingOccurrences(of: " ", with: "")
        guard let m = t.wholeMatch(of: /([A-Z0-9]{2}[A-Z]?)(\d{1,4}[A-Z]?)/) else { return nil }
        let carrier = String(m.1)
        guard carrier.contains(where: \.isLetter) else { return nil }
        return (carrier, String(m.2))
    }
}

/// Parser for AeroDataBox "Flight status (single day)" responses (`GET /flights/Number/{n}/{date}`),
/// per its published OpenAPI schema (FlightContract). Times come as `{utc, local}`; we use `utc`.
public enum AeroDataBoxParser {
    struct Flight: Decodable {
        var number: String
        var status: String?
        var codeshareStatus: String?
        var isCargo: Bool?
        var airline: Airline?
        var departure: Movement
        var arrival: Movement
    }
    struct Airline: Decodable { var name: String?; var iata: String? }
    struct Movement: Decodable { var airport: AirportInfo; var scheduledTime: TimePair? }
    struct AirportInfo: Decodable {
        var iata: String?; var name: String?; var shortName: String?; var municipalityName: String?; var timeZone: String?
    }
    struct TimePair: Decodable { var utc: String?; var local: String? }

    /// An empty body (HTTP 204) means no flights.
    public static func parse(_ data: Data) throws -> [FlightOption] {
        if data.isEmpty { return [] }
        let flights = try JSONDecoder().decode([Flight].self, from: data)
        return flights.compactMap(option).sorted { $0.departure < $1.departure }
    }

    static func option(_ f: Flight) -> FlightOption? {
        guard f.isCargo != true,
              let o = f.departure.airport.iata?.uppercased(), let d = f.arrival.airport.iata?.uppercased(),
              let dep = f.departure.scheduledTime?.utc.flatMap(parseUTC),
              let arr = f.arrival.scheduledTime?.utc.flatMap(parseUTC), arr > dep,
              let oz = zone(f.departure.airport.timeZone, o), let dz = zone(f.arrival.airport.timeZone, d)
        else { return nil }
        let parsed = FlightNumberParser.parse(f.number)
        return FlightOption(flightNumber: f.number, carrierCode: parsed?.carrier ?? f.airline?.iata, number: parsed?.number,
                            airlineName: f.airline?.name, origin: o, destination: d,
                            originName: f.departure.airport.municipalityName ?? f.departure.airport.shortName ?? f.departure.airport.name,
                            destinationName: f.arrival.airport.municipalityName ?? f.arrival.airport.shortName ?? f.arrival.airport.name,
                            originZoneID: oz, destinationZoneID: dz, departure: dep, arrival: arr,
                            isCodeshare: f.codeshareStatus == "IsCodeshared", status: f.status)
    }

    /// Provider zone if it's a valid IANA id, else the bundled airport table. Otherwise nil (not guessed).
    static func zone(_ provided: String?, _ iata: String) -> String? {
        if let p = provided, TimeZone(identifier: p) != nil { return p }
        return Airports.lookup(iata)?.zoneID
    }

    /// Accepts "2026-11-23 12:30Z", "2026-11-23T12:30Z", "2026-11-23T12:30:00Z", "2026-11-23 12:30+00:00".
    static func parseUTC(_ s: String) -> Date? {
        let t = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "T")
        let iso = ISO8601DateFormatter()
        for opts: ISO8601DateFormatter.Options in [[.withInternetDateTime], [.withInternetDateTime, .withFractionalSeconds]] {
            iso.formatOptions = opts
            if let d = iso.date(from: t) { return d }
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
        for fmt in ["yyyy-MM-dd'T'HH:mmXXXXX", "yyyy-MM-dd'T'HH:mmX", "yyyy-MM-dd'T'HH:mm"] {
            f.dateFormat = fmt
            if let d = f.date(from: t) { return d }
        }
        return nil
    }
}
