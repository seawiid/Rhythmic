import Foundation
import Testing
@testable import RhythmicCore

@Suite("Itinerary import and normalisation")
struct ImportTests {
    func imported(_ kind: SourceKind, _ id: String, updated: Date? = nil, carrier: String? = "ET", number: String? = "646",
                  o: String? = "WDH", d: String? = "ADD",
                  dep: LocalDateTime? = .init(2026, 11, 23, 14, 30), arr: LocalDateTime? = .init(2026, 11, 23, 21, 20),
                  cancelled: Bool = false) -> ImportedSegment {
        ImportedSegment(source: SourceRef(kind: kind, externalID: id, updatedAt: updated), carrierCode: carrier, flightNumber: number,
                        origin: o, destination: d,
                        departure: dep.map { .local($0, zoneID: nil) }, arrival: arr.map { .local($0, zoneID: nil) },
                        cancelled: cancelled, rawSummary: "\(carrier ?? "") \(number ?? "") \(o ?? "?") to \(d ?? "?")")
    }

    @Test("Connecting segments are grouped into one trip; distant flights are separate trips")
    func grouping() {
        let r = ItineraryNormalizer.normalize([
            imported(.manual, "a"),
            imported(.manual, "b", carrier: "ET", number: "638", o: "ADD", d: "SIN", dep: .init(2026, 11, 24, 0, 10), arr: .init(2026, 11, 24, 14, 50)),
            imported(.manual, "c", carrier: "SQ", number: "1", o: "SIN", d: "JNB", dep: .init(2026, 12, 5, 1, 0), arr: .init(2026, 12, 5, 6, 0)),
        ])
        #expect(r.trips.count == 2)
        #expect(r.trips[0].segments.count == 2)
        #expect(r.trips[0].title == "WDH → ADD → SIN")
        #expect(r.issues.isEmpty)
    }

    @Test("Duplicates across sources merge into one segment with both source ids")
    func duplicates() {
        let r = ItineraryNormalizer.normalize([imported(.googleCalendar, "g1"), imported(.tripItFeed, "t1")])
        #expect(r.trips.count == 1)
        #expect(r.trips[0].segments.count == 1)
        #expect(Set(r.trips[0].segments[0].sources.map(\.kind)) == [.googleCalendar, .tripItFeed])
    }

    @Test("Conflicting times across sources: newest wins and an issue is raised")
    func conflicts() {
        let r = ItineraryNormalizer.normalize([
            imported(.googleCalendar, "g1", updated: Date(timeIntervalSince1970: 100)),
            imported(.tripItFeed, "t1", updated: Date(timeIntervalSince1970: 200), dep: .init(2026, 11, 23, 15, 30), arr: .init(2026, 11, 23, 22, 20)),
        ])
        #expect(r.issues.contains { $0.kind == .conflictingSources })
        #expect(local(r.trips[0].segments[0].departure, "Africa/Windhoek") == "2026-11-23 15:30")
    }

    @Test("A newer version of the same source event replaces the older one")
    func updates() {
        let r = ItineraryNormalizer.normalize([
            imported(.googleCalendar, "g1", updated: Date(timeIntervalSince1970: 200), dep: .init(2026, 11, 23, 16, 0), arr: .init(2026, 11, 23, 22, 50)),
            imported(.googleCalendar, "g1", updated: Date(timeIntervalSince1970: 100)),
        ])
        #expect(r.trips.flatMap(\.segments).count == 1)
        #expect(local(r.trips[0].segments[0].departure, "Africa/Windhoek") == "2026-11-23 16:00")
    }

    @Test("Cancellation removes the flight from trips")
    func cancellation() {
        let r = ItineraryNormalizer.normalize([
            imported(.googleCalendar, "g1", updated: Date(timeIntervalSince1970: 100)),
            imported(.googleCalendar, "g1", updated: Date(timeIntervalSince1970: 300), cancelled: true),
        ])
        #expect(r.trips.isEmpty)
        #expect(r.cancelled.count == 1)
    }

    @Test("Missing fields and unknown airports become issues; nothing is invented")
    func missing() {
        let r = ItineraryNormalizer.normalize([
            imported(.googleCalendar, "m1", o: nil),
            imported(.googleCalendar, "m2", o: "XYZ"),
            imported(.googleCalendar, "m3", arr: nil),
        ])
        #expect(r.trips.isEmpty)
        #expect(r.incomplete.count == 3)
        #expect(r.issues.map(\.kind).sorted { $0.rawValue < $1.rawValue } == [.missingField, .missingField, .unknownAirport])
    }

    @Test("Ambiguous local times are not guessed")
    func ambiguous() {
        let r = ItineraryNormalizer.normalize([
            imported(.manual, "x", carrier: "AA", number: "1", o: "JFK", d: "ORD", dep: .init(2026, 11, 1, 1, 30), arr: .init(2026, 11, 1, 3, 0)),
        ])
        #expect(r.trips.isEmpty)
        #expect(r.issues.first?.kind == .ambiguousLocalTime)
    }

    @Test("ICS feed (synthetic sample — not a real TripIt export)")
    func ics() {
        let ics = """
        BEGIN:VCALENDAR\r
        VERSION:2.0\r
        BEGIN:VEVENT\r
        UID:item-1@example\r
        DTSTAMP:20261101T120000Z\r
        SUMMARY:ET646 WDH to ADD\r
        DTSTART;TZID=Africa/Windhoek:20261123T143000\r
        DTEND;TZID=Africa/Addis_Ababa:20261123T212000\r
        END:VEVENT\r
        BEGIN:VEVENT\r
        UID:item-2@example\r
        SUMMARY:ET 638 ADD to SIN\r
        DTSTART:20261123T211000Z\r
        DTEND:20261124T065000Z\r
        LOCATION:Addis Ababa (ADD)\r
        END:VEVENT\r
        BEGIN:VEVENT\r
        UID:hotel-1@example\r
        SUMMARY:Hotel check-in\r
        DTSTART:20261124T080000Z\r
        DTEND:20261124T090000Z\r
        END:VEVENT\r
        BEGIN:VEVENT\r
        UID:trip-only@example\r
        SUMMARY:Singapore trip\r
        DTSTART:20261123T080000Z\r
        DTEND:20261126T090000Z\r
        END:VEVENT\r
        END:VCALENDAR\r
        """
        let segs = ICSParser.segments(from: ics)
        #expect(segs.count == 2)  // hotel and trip-title-only events are ignored
        let r = ItineraryNormalizer.normalize(segs)
        #expect(r.trips.count == 1)
        #expect(r.trips[0].segments.map(\.flightNumber) == ["646", "638"])
        #expect(local(r.trips[0].arrival, "Asia/Singapore") == "2026-11-24 14:50")
    }

    @Test("Google Calendar events JSON (synthetic sample) — incomplete fromGmail events are flagged")
    func google() throws {
        let json = """
        {"items":[
          {"id":"e1","eventType":"fromGmail","status":"confirmed","updated":"2026-11-01T10:00:00.000Z",
           "summary":"Flight to Addis Ababa (ET 646)","location":"Windhoek WDH",
           "start":{"dateTime":"2026-11-23T14:30:00+02:00","timeZone":"Africa/Windhoek"},
           "end":{"dateTime":"2026-11-23T21:20:00+03:00","timeZone":"Africa/Addis_Ababa"}},
          {"id":"e2","eventType":"default","summary":"Flight ADD-SIN ET638",
           "start":{"dateTime":"2026-11-24T00:10:00+03:00"},"end":{"dateTime":"2026-11-24T14:50:00+08:00"}},
          {"id":"e3","eventType":"default","summary":"Dentist","start":{"dateTime":"2026-11-20T09:00:00+02:00"},"end":{"dateTime":"2026-11-20T10:00:00+02:00"}}
        ]}
        """
        let segs = try GoogleCalendarEventParser.segments(fromEventsListJSON: Data(json.utf8))
        #expect(segs.count == 2)
        let r = ItineraryNormalizer.normalize(segs)
        // e1 has no machine-readable route in this sample → asked, not guessed.
        #expect(r.incomplete.count == 1)
        #expect(r.trips.count == 1)
        #expect(r.trips[0].segments[0].origin == "ADD")
    }

    @Test("Trip title shows a ground transfer between airports")
    func groundTransferTitle() {
        let t = Trip(id: "x", segments: [
            seg("a", "WDH", "JNB", dep: .init(2026, 11, 17, 7, 0), arr: .init(2026, 11, 17, 9, 0)),
            seg("b", "SIN", "ADD", dep: .init(2026, 11, 18, 2, 0), arr: .init(2026, 11, 18, 6, 0)),
        ])
        #expect(t.title == "WDH → JNB / SIN → ADD")
        #expect(Fixtures.namibiaSingapore.title == "WDH → ADD → SIN")
    }

    @Test("Pasted feed links are cleaned up; non-links and plain http are refused")
    func feedLinks() throws {
        let good = "https://www.tripit.com/feed/ical/private/ABC-123/tripit.ics"
        for raw in ["webcal://www.tripit.com/feed/ical/private/ABC-123/tripit.ics",
                    "  webcal://www.tripit.com/feed/ical/private/ABC-123/tripit.ics\n",
                    "<https://www.tripit.com/feed/ical/private/ABC-123/tripit.ics>",
                    "Your feed: \"webcal://www.tripit.com/feed/ical/private/ABC-123/tripit.ics\" (keep private)",
                    "WEBCAL://www.tripit.com/feed/ical/private/ABC-123/tripit.ics"] {
            #expect(try FeedLink.normalize(raw).get().absoluteString.lowercased() == good.lowercased(), "\(raw)")
        }
        #expect(FeedLink.normalize("   ") == .failure(.empty))
        #expect(FeedLink.normalize("my tripit feed") == .failure(.noLink))
        #expect(FeedLink.normalize("http://example.com/a.ics") == .failure(.notSecure))
    }

    @Test("Past flights from a feed are hidden, including their review items; a kept trip stays")
    func upcomingOnly() {
        func raw(_ id: String, _ o: String, _ d: String, _ dep: Date, _ hours: Double) -> ImportedSegment {
            ImportedSegment(source: SourceRef(kind: .tripItFeed, externalID: id), origin: o, destination: d,
                            departure: .instant(dep), arrival: .instant(dep.addingTimeInterval(hours * 3600)))
        }
        let now = LocalDateTime(2026, 11, 17, 12, 0).date(in: "UTC")
        let day: TimeInterval = 86400
        let input = [
            raw("past", "SIN", "ADD", now.addingTimeInterval(-30 * day), 9),
            raw("past-unknown", "SIN", "ZZZ", now.addingTimeInterval(-20 * day), 3),   // past + unknown airport
            raw("soon-unknown", "SIN", "ZZZ", now.addingTimeInterval(20 * day), 3),    // future + unknown airport
            raw("future", "WDH", "ADD", now.addingTimeInterval(6 * day), 7),
        ]
        let all = ItineraryNormalizer.normalize(input)
        let r = all.upcoming(from: input, now: now, keepTripID: nil)
        #expect(r.trips.map(\.first.origin) == ["WDH"])
        #expect(r.issues.count == 1 && r.issues[0].source?.externalID == "soon-unknown")
        #expect(r.incomplete.map(\.source.externalID) == ["soon-unknown"])
        // The selected trip is kept even if it ended.
        let kept = all.upcoming(from: input, now: now, keepTripID: all.trips.first { $0.first.origin == "SIN" }?.id)
        #expect(kept.trips.count == 2)
    }

    @Test("Bundled airport table covers airports beyond the hand-checked list; hand-checked entries win")
    func airportTable() throws {
        #expect(Airports.extended.count > 7000)
        #expect(Airports.lookup("KIX")?.zoneID == "Asia/Tokyo")
        #expect(Airports.lookup("can")?.zoneID == "Asia/Shanghai")
        #expect(Airports.lookup("SZB")?.zoneID == "Asia/Kuala_Lumpur")
        #expect(Airports.lookup("XSP")?.zoneID == "Asia/Singapore")   // correction wins
        #expect(Airports.lookup("WDH")?.city == "Windhoek")
        #expect(Airports.lookup("QQQ") == nil)
        // A feed flight to a formerly unknown airport now resolves.
        let raw = ImportedSegment(source: SourceRef(kind: .tripItFeed, externalID: "k"), origin: "SIN", destination: "KIX",
                                  departure: .instant(Date(timeIntervalSince1970: 1_798_000_000)),
                                  arrival: .instant(Date(timeIntervalSince1970: 1_798_021_600)))
        let r = ItineraryNormalizer.normalize([raw])
        #expect(r.issues.isEmpty)
        #expect(r.trips.first?.last.destinationZoneID == "Asia/Tokyo")
    }
}
