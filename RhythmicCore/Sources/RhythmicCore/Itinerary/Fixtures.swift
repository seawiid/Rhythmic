import Foundation

/// Sample itineraries. Always labelled as samples in the UI — never presented as imported data.
public enum Fixtures {
    static let sample = SourceRef(kind: .sample, externalID: "fixture")

    /// Real example from the brief: Windhoek → Addis Ababa → Singapore, 23–24 Nov 2026.
    /// Flight numbers are deliberately omitted (not provided); the UI shows route only.
    public static let namibiaSingapore = Trip(id: "sample-wdh-sin", segments: [
        FlightSegment(id: "sample-wdh-add", origin: "WDH", destination: "ADD",
                      originZoneID: "Africa/Windhoek", destinationZoneID: "Africa/Addis_Ababa",
                      departure: LocalDateTime(2026, 11, 23, 14, 30).date(in: "Africa/Windhoek"),
                      arrival: LocalDateTime(2026, 11, 23, 21, 20).date(in: "Africa/Addis_Ababa"),
                      sources: [sample]),
        FlightSegment(id: "sample-add-sin", origin: "ADD", destination: "SIN",
                      originZoneID: "Africa/Addis_Ababa", destinationZoneID: "Asia/Singapore",
                      departure: LocalDateTime(2026, 11, 24, 0, 10).date(in: "Africa/Addis_Ababa"),
                      arrival: LocalDateTime(2026, 11, 24, 14, 50).date(in: "Asia/Singapore"),
                      sources: [sample]),
    ])

    /// Westward test from the brief. No real date was given:
    /// FIXTURE DATE 10 Dec 2026 is an arbitrary label, not a real booking.
    public static let singaporeUganda = Trip(id: "sample-sin-ebb", segments: [
        FlightSegment(id: "sample-sin-add", origin: "SIN", destination: "ADD",
                      originZoneID: "Asia/Singapore", destinationZoneID: "Africa/Addis_Ababa",
                      departure: LocalDateTime(2026, 12, 10, 2, 0).date(in: "Asia/Singapore"),
                      arrival: LocalDateTime(2026, 12, 10, 2, 0).date(in: "Asia/Singapore").adding(hours: 9),
                      sources: [sample]),
        FlightSegment(id: "sample-add-ebb", origin: "ADD", destination: "EBB",
                      originZoneID: "Africa/Addis_Ababa", destinationZoneID: "Africa/Kampala",
                      departure: LocalDateTime(2026, 12, 10, 2, 0).date(in: "Asia/Singapore").adding(hours: 11),
                      arrival: LocalDateTime(2026, 12, 10, 2, 0).date(in: "Asia/Singapore").adding(hours: 13),
                      sources: [sample]),
    ])

    /// Preferences for the westward test: same habits, home in Singapore.
    public static let singaporeHomePrefs: Preferences = {
        var p = Preferences.demo
        p.homeZoneID = "Asia/Singapore"
        return p
    }()
}
