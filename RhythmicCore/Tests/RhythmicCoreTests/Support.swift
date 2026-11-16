import Foundation
@testable import RhythmicCore

/// Engineering-validation helpers. These tests check internal consistency and time maths —
/// they are NOT clinical validation, and fixture times are not expected "correct" schedules.

func seg(_ id: String, _ o: String, _ d: String, dep: LocalDateTime, arr: LocalDateTime) -> FlightSegment {
    let oz = Airports.lookup(o)!.zoneID, dz = Airports.lookup(d)!.zoneID
    return FlightSegment(id: id, origin: o, destination: d, originZoneID: oz, destinationZoneID: dz,
                         departure: dep.date(in: oz), arrival: arr.date(in: dz),
                         sources: [SourceRef(kind: .sample, externalID: id)])
}

func plan(_ trip: Trip, _ prefs: Preferences = .demo) -> Plan {
    guard case .plan(let p) = Planner().makePlan(trip: trip, preferences: prefs) else {
        fatalError("expected a plan for \(trip.title)")
    }
    return p
}

func local(_ d: Date, _ zone: String) -> String {
    let f = DateFormatter()
    f.timeZone = TimeZone(identifier: zone); f.locale = Locale(identifier: "en_GB"); f.dateFormat = "yyyy-MM-dd HH:mm"
    return f.string(from: d)
}

/// A spread of scenarios used by the invariant tests.
enum Scenarios {
    static let demoEast = (Fixtures.namibiaSingapore, Preferences.demo)
    static let demoEastSleepsOnFlights: (Trip, Preferences) = {
        var p = Preferences.demo; p.rarelySleepsOnDaytimeFlights = false; return (Fixtures.namibiaSingapore, p)
    }()
    static let west = (Fixtures.singaporeUganda, Fixtures.singaporeHomePrefs)

    /// Honolulu → Tokyo crosses the date line westbound (Tokyo is 19 h ahead = 5 h "behind, next day").
    static let dateLine: (Trip, Preferences) = {
        var p = Preferences.demo; p.homeZoneID = "Pacific/Honolulu"
        return (Trip(id: "hnl-nrt", segments: [seg("hnl-nrt", "HNL", "NRT", dep: .init(2026, 6, 10, 13, 0), arr: .init(2026, 6, 11, 17, 0))]), p)
    }()

    /// New York → London departing the day after US DST ends (prep nights span 1 Nov 2026 fall-back).
    static let dst: (Trip, Preferences) = {
        var p = Preferences.demo; p.homeZoneID = "America/New_York"; p.preTravelShift = .standard
        return (Trip(id: "jfk-lhr", segments: [seg("jfk-lhr", "JFK", "LHR", dep: .init(2026, 11, 2, 19, 0), arr: .init(2026, 11, 3, 7, 0))]), p)
    }()

    /// London → Kathmandu (+5:45 fractional offset).
    static let fractional: (Trip, Preferences) = {
        var p = Preferences.demo; p.homeZoneID = "Europe/London"
        return (Trip(id: "lhr-ktm", segments: [
            seg("lhr-del", "LHR", "DEL", dep: .init(2026, 11, 10, 21, 0), arr: .init(2026, 11, 11, 10, 30)),
            seg("del-ktm", "DEL", "KTM", dep: .init(2026, 11, 11, 13, 0), arr: .init(2026, 11, 11, 14, 45)),
        ]), p)
    }()

    /// Very large eastward change (New York → Singapore, Δ = +13 → treated as 11 h).
    static let large: (Trip, Preferences) = {
        var p = Preferences.demo; p.homeZoneID = "America/New_York"; p.caffeineSensitive = true
        return (Trip(id: "jfk-sin", segments: [seg("jfk-sin", "JFK", "SIN", dep: .init(2026, 12, 1, 22, 0), arr: .init(2026, 12, 3, 5, 30))]), p)
    }()

    /// Afternoon long-haul whose duration overlaps destination night — the case where a reference
    /// app scheduled most sleep on an afternoon flight.
    static let afternoonLongHaul: (Trip, Preferences) = {
        var p = Preferences.demo; p.homeZoneID = "Africa/Johannesburg"
        return (Trip(id: "jnb-sin", segments: [seg("jnb-sin", "JNB", "SIN", dep: .init(2026, 11, 23, 13, 0), arr: .init(2026, 11, 24, 6, 0))]), p)
    }()

    static let noCaffeine: (Trip, Preferences) = {
        var p = Preferences.demo; p.caffeine = .none; return (Fixtures.namibiaSingapore, p)
    }()

    static let all: [(String, Trip, Preferences)] = [
        ("demoEast", demoEast.0, demoEast.1),
        ("demoEastSleepsOnFlights", demoEastSleepsOnFlights.0, demoEastSleepsOnFlights.1),
        ("west", west.0, west.1),
        ("dateLine", dateLine.0, dateLine.1),
        ("dst", dst.0, dst.1),
        ("fractional", fractional.0, fractional.1),
        ("large", large.0, large.1),
        ("afternoonLongHaul", afternoonLongHaul.0, afternoonLongHaul.1),
        ("noCaffeine", noCaffeine.0, noCaffeine.1),
    ]
}
