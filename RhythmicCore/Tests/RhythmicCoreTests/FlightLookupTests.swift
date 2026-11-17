import Foundation
import Testing
@testable import RhythmicCore

/// SYNTHETIC responses shaped after AeroDataBox's published OpenAPI schema (no real response was
/// available when this was written). Validate against a live response before relying on it.
@Suite("Flight-number lookup (AeroDataBox, synthetic)")
struct FlightLookupTests {
    let twoLegs = """
    [
      {"number":"ET 646","status":"Expected","codeshareStatus":"IsOperator","isCargo":false,
       "lastUpdatedUtc":"2026-11-17 06:00Z","airline":{"name":"Ethiopian","iata":"ET"},
       "departure":{"airport":{"iata":"WDH","name":"Windhoek Hosea Kutako","municipalityName":"Windhoek","timeZone":"Africa/Windhoek"},
                    "scheduledTime":{"utc":"2026-11-23 12:30Z","local":"2026-11-23 14:30+02:00"}},
       "arrival":{"airport":{"iata":"ADD","name":"Addis Ababa Bole","municipalityName":"Addis Ababa","timeZone":"Africa/Addis_Ababa"},
                  "scheduledTime":{"utc":"2026-11-23T18:20:00Z","local":"2026-11-23 21:20+03:00"}}},
      {"number":"ET 646","status":"Expected","codeshareStatus":"IsOperator","isCargo":false,
       "lastUpdatedUtc":"2026-11-17 06:00Z","airline":{"name":"Ethiopian","iata":"ET"},
       "departure":{"airport":{"iata":"XXA","name":"Unknown field","timeZone":null},
                    "scheduledTime":{"utc":"2026-11-23 08:00Z","local":"2026-11-23 10:00+02:00"}},
       "arrival":{"airport":{"iata":"WDH","name":"Windhoek","timeZone":"Africa/Windhoek"},
                  "scheduledTime":{"utc":"2026-11-23 10:00Z","local":"2026-11-23 12:00+02:00"}}},
      {"number":"ET 3646","status":"Expected","codeshareStatus":"IsOperator","isCargo":true,
       "lastUpdatedUtc":"2026-11-17 06:00Z","airline":{"name":"Ethiopian Cargo"},
       "departure":{"airport":{"iata":"WDH","name":"Windhoek","timeZone":"Africa/Windhoek"},"scheduledTime":{"utc":"2026-11-23 01:00Z","local":""}},
       "arrival":{"airport":{"iata":"ADD","name":"Addis","timeZone":"Africa/Addis_Ababa"},"scheduledTime":{"utc":"2026-11-23 07:00Z","local":""}}}
    ]
    """

    @Test("Legs become options with absolute times and airport zones; incomplete and cargo legs are dropped")
    func parse() throws {
        let opts = try AeroDataBoxParser.parse(Data(twoLegs.utf8))
        #expect(opts.count == 1)  // unknown-zone leg and cargo dropped, not guessed
        let o = try #require(opts.first)
        #expect(o.origin == "WDH" && o.destination == "ADD")
        #expect(o.carrierCode == "ET" && o.number == "646")
        #expect(local(o.departure, o.originZoneID) == "2026-11-23 14:30")
        #expect(local(o.arrival, o.destinationZoneID) == "2026-11-23 21:20")
        #expect(o.originName == "Windhoek")
    }

    @Test("A looked-up leg normalises exactly like the brief's flight")
    func normalises() throws {
        let o = try #require(try AeroDataBoxParser.parse(Data(twoLegs.utf8)).first)
        let r = ItineraryNormalizer.normalize([o.importedSegment(externalID: "x", fetchedAt: Date())])
        let s = try #require(r.trips.first?.segments.first)
        #expect(s.departure == Fixtures.namibiaSingapore.segments[0].departure)
        #expect(s.arrival == Fixtures.namibiaSingapore.segments[0].arrival)
        #expect(r.issues.isEmpty)
    }

    @Test("Empty body (HTTP 204) means no flights")
    func empty() throws {
        #expect(try AeroDataBoxParser.parse(Data()).isEmpty)
        #expect(try AeroDataBoxParser.parse(Data("[]".utf8)).isEmpty)
    }

    @Test("Flight numbers are split into airline code and number")
    func numbers() {
        #expect(FlightNumberParser.parse("ET646")! == ("ET", "646"))
        #expect(FlightNumberParser.parse("et 646")! == ("ET", "646"))
        #expect(FlightNumberParser.parse("9W 123")! == ("9W", "123"))
        #expect(FlightNumberParser.parse("12 345") == nil)
        #expect(FlightNumberParser.parse("hello") == nil)
    }
}
