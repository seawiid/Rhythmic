import Foundation
import Testing
@testable import RhythmicCore

@Suite("Time zones and itinerary maths")
struct TimeZoneTests {
    let trip = Fixtures.namibiaSingapore
    let nam = "Africa/Windhoek"

    @Test("Offsets on the demo dates match the brief")
    func offsets() {
        #expect(Zone.offsetHours("Africa/Windhoek", at: trip.departure) == 2)
        #expect(Zone.offsetHours("Africa/Addis_Ababa", at: trip.departure) == 3)
        #expect(Zone.offsetHours("Asia/Singapore", at: trip.arrival) == 8)
    }

    @Test("Verified conversions from the brief")
    func briefConversions() {
        let s = trip.segments
        #expect(local(s[0].arrival, nam) == "2026-11-23 20:20")
        #expect(local(s[1].departure, nam) == "2026-11-23 23:10")
        #expect(local(s[1].arrival, nam) == "2026-11-24 08:50")
        #expect(local(LocalDateTime(2026, 11, 25, 5, 0).date(in: "Asia/Singapore"), nam) == "2026-11-24 23:00")
        // Transit 2 h 50 min
        #expect(s[1].departure.timeIntervalSince(s[0].arrival) == (2 * 60 + 50) * 60)
    }

    @Test("Westward fixture arrives 10:00 East Africa time, not 11:00")
    func westArrival() {
        let t = Fixtures.singaporeUganda
        #expect(local(t.arrival, "Africa/Kampala") == "2026-12-10 10:00")
        #expect(local(t.segments[0].arrival, "Africa/Addis_Ababa") == "2026-12-10 06:00")
        #expect(t.segments[1].departure.timeIntervalSince(t.segments[0].arrival) == 2 * 3600)
    }

    @Test("Local times are resolved explicitly across DST")
    func dstResolution() {
        let ny = TimeZone(identifier: "America/New_York")!
        guard case .ambiguous(let a, let b) = LocalDateTime(2026, 11, 1, 1, 30).resolve(in: ny) else {
            Issue.record("01:30 on 1 Nov 2026 in New York should be ambiguous"); return
        }
        #expect(b.timeIntervalSince(a) == 3600)
        #expect(LocalDateTime(2026, 3, 8, 2, 30).resolve(in: ny) == .nonexistent)
        if case .unique = LocalDateTime(2026, 11, 1, 3, 0).resolve(in: ny) {} else { Issue.record("03:00 should be unique") }
    }

    @Test("Fractional offsets are handled")
    func fractional() {
        #expect(Zone.offsetHours("Asia/Kathmandu", at: Date(timeIntervalSince1970: 1_790_000_000)) == 5.75)
        #expect(Zone.offsetHours("Asia/Kolkata", at: Date(timeIntervalSince1970: 1_790_000_000)) == 5.5)
    }

    @Test("Trip location zone follows the traveller, with explicit dates across midnight")
    func zoneTimeline() {
        let s = trip.segments
        #expect(trip.zoneID(at: s[0].departure.addingTimeInterval(-60)) == "Africa/Windhoek")
        #expect(trip.zoneID(at: s[0].departure.addingTimeInterval(60)) == "Africa/Addis_Ababa")
        #expect(trip.zoneID(at: s[1].departure.addingTimeInterval(60)) == "Asia/Singapore")
        #expect(local(s[1].departure, "Africa/Addis_Ababa") == "2026-11-24 00:10")
    }

    @Test("Direction chosen across the date line and for very large shifts")
    func direction() {
        let dl = plan(Scenarios.dateLine.0, Scenarios.dateLine.1)
        #expect(dl.strategy.zoneDifferenceHours == -5)
        #expect(dl.strategy.direction == .delay)

        let big = plan(Scenarios.large.0, Scenarios.large.1)
        #expect(big.strategy.zoneDifferenceHours == -11)  // +13 normalised
        #expect(big.strategy.direction == .delay)
        #expect(big.warnings.contains { $0.message.contains("very large") })

        let east = plan(Fixtures.namibiaSingapore)
        #expect(east.strategy.direction == .advance)
        #expect(east.strategy.shiftHours == 6)
    }
}
