import Foundation
import Testing
@testable import RhythmicCore

@Suite("Timeline layout")
struct TimelineLayoutTests {
    let trip = Fixtures.namibiaSingapore
    let metrics = LabelMetrics(timeHeight: 14, cityHeight: 12)

    @Test("Clock follows the most recently reached place and switches at landing, not takeoff")
    func clockZone() {
        let s = trip.segments
        #expect(trip.clockZoneID(at: s[0].departure.addingTimeInterval(-1)) == "Africa/Windhoek")
        #expect(trip.clockZoneID(at: s[0].departure.addingTimeInterval(60)) == "Africa/Windhoek")  // airborne
        #expect(trip.clockZoneID(at: s[0].arrival.addingTimeInterval(-1)) == "Africa/Windhoek")
        #expect(trip.clockZoneID(at: s[0].arrival) == "Africa/Addis_Ababa")                       // exact landing instant
        #expect(trip.clockZoneID(at: s[1].departure.addingTimeInterval(3600)) == "Africa/Addis_Ababa")  // next flight
        #expect(trip.clockZoneID(at: s[1].arrival.addingTimeInterval(-1)) == "Africa/Addis_Ababa")
        #expect(trip.clockZoneID(at: s[1].arrival) == "Asia/Singapore")
        #expect(trip.clockCity(at: s[0].arrival) == "Addis Ababa")
    }

    @Test("Flight events show the brief's local times, each on exactly one day")
    func flightEventsOnDays() {
        let pl = plan(trip)
        let days = TimelineLayout.days(for: pl)
        let all = days.flatMap { d in TimelineLayout.flightEvents(pl.trip, in: d.span).map { (d, $0) } }
        #expect(all.count == 4)
        #expect(Set(all.map(\.1.id)).count == 4, "no event is rendered twice")
        let shown = all.map { "\($0.0.day) \($0.1.kind) \(local($0.1.date, pl.trip.clockZoneID(at: $0.1.date)))" }
        #expect(shown == ["23 takeoff 2026-11-23 14:30", "23 landing 2026-11-23 21:20",
                          "24 takeoff 2026-11-24 00:10", "24 landing 2026-11-24 14:50"])
        // Addis landing is 20:20 in Namibia.
        #expect(local(all[1].1.date, "Africa/Windhoek") == "2026-11-23 20:20")
    }

    @Test("Days are contiguous, cover the horizon, and change length with the clock zone")
    func dayPartition() {
        let pl = plan(trip)
        let days = TimelineLayout.days(for: pl)
        #expect(days.first?.span.start == pl.horizon.start)
        #expect(days.last?.span.end == pl.horizon.end)
        for (a, b) in zip(days, days.dropFirst()) { #expect(a.span.end == b.span.start) }
        let d23 = days.first { $0.day == 23 }!, d24 = days.first { $0.day == 24 }!
        #expect(d23.span.duration == 23 * 3600)   // Namibia midnight → Addis midnight
        #expect(d24.span.duration == 19 * 3600)   // Addis midnight → Singapore midnight
        #expect(d24.zoneIDAtStart == "Africa/Addis_Ababa")
        #expect(days.map(\.day) == [21, 22, 23, 24, 25, 26])
    }

    @Test("Days stay contiguous and ordered in every scenario (date line, DST, fractional offsets)", arguments: Scenarios.all.map(\.0))
    func dayInvariants(_ name: String) {
        let s = Scenarios.all.first { $0.0 == name }!
        let pl = plan(s.1, s.2)
        let days = TimelineLayout.days(for: pl)
        #expect(days.first?.span.start == pl.horizon.start)
        #expect(days.last?.span.end == pl.horizon.end)
        for (a, b) in zip(days, days.dropFirst()) {
            #expect(a.span.end == b.span.start)
            #expect(!a.span.isEmpty)
        }
        // Every flight event appears exactly once.
        let events = days.flatMap { TimelineLayout.flightEvents(pl.trip, in: $0.span) }
        #expect(events.count == pl.trip.segments.count * 2)
        #expect(Set(events.map(\.id)).count == events.count)
    }

    @Test("An event exactly at local midnight belongs to the next day only")
    func midnightEvent() {
        let t = Trip(id: "mid", segments: [seg("wdh-jnb", "WDH", "JNB", dep: .init(2026, 11, 24, 0, 0), arr: .init(2026, 11, 24, 2, 0))])
        let pl = plan(t)
        let days = TimelineLayout.days(for: pl)
        let hits = days.filter { !TimelineLayout.flightEvents(pl.trip, in: $0.span).filter { $0.kind == .takeoff }.isEmpty }
        #expect(hits.count == 1)
        #expect(hits.first?.day == 24)
        // It replaces the day-start label rather than stacking on it.
        let labels = TimelineLayout.labels(pl, day: hits[0], pointsPerHour: 40, metrics: metrics)
        #expect(labels.filter { $0.y == 0 }.count == 1)
    }

    @Test("Main and caffeine lanes neither overlap nor lose or duplicate time across midnight", arguments: Scenarios.all.map(\.0))
    func lanesContinuous(_ name: String) {
        let s = Scenarios.all.first { $0.0 == name }!
        let pl = plan(s.1, s.2)
        let days = TimelineLayout.days(for: pl)
        var mainTotal: TimeInterval = 0, caffeineTotal: TimeInterval = 0
        for d in days {
            let main = TimelineLayout.mainLane(pl, in: d.span)
            for (a, b) in zip(main, main.dropFirst()) { #expect(a.span.end <= b.span.start, "overlap in main lane") }
            #expect(main.allSatisfy { d.span.start <= $0.span.start && $0.span.end <= d.span.end })
            mainTotal += main.map(\.span.duration).reduce(0, +)
            caffeineTotal += TimelineLayout.caffeineLane(pl, in: d.span).map(\.span.duration).reduce(0, +)
        }
        // Union of the main-lane kinds, computed independently.
        let kinds: Set<BlockKind> = [.sleep, .nap, .prioritizeLight, .reduceLight, .lightHelpful]
        var union: [TimeSpan] = []
        for b in pl.blocks where kinds.contains(b.kind) {
            union += b.span.subtracting(union)
        }
        #expect(abs(mainTotal - union.map(\.duration).reduce(0, +)) < 60 * 5)
        let caffeine = pl.blocks.filter { $0.kind.lane == .caffeine }.map(\.span.duration).reduce(0, +)
        #expect(abs(caffeineTotal - caffeine) < 60 * 5)
    }

    @Test("Blocks keep their elapsed-time geometry across a zone change")
    func proportional() {
        let pl = plan(trip)
        let d23 = TimelineLayout.days(for: pl).first { $0.day == 23 }!
        let landing = trip.segments[0].arrival
        let labels = TimelineLayout.labels(pl, day: d23, pointsPerHour: 40, metrics: metrics)
        let l = labels.first { $0.kind == .event(.landing) }!
        #expect(l.y == CGFloat(landing.timeIntervalSince(d23.span.start) / 3600) * 40)
        #expect(l.city == "Addis Ababa")
        #expect(l.zoneID == "Africa/Addis_Ababa")
        // Takeoff from Windhoek: exact position, no city (zone hasn't changed).
        let t = labels.first { $0.kind == .event(.takeoff) }!
        #expect(t.y == CGFloat(trip.segments[0].departure.timeIntervalSince(d23.span.start) / 3600) * 40)
        #expect(t.city == nil)
        // Hour labels after landing are in Addis time (on the hour there).
        let after = labels.filter { $0.kind == .hour && $0.date > landing }
        #expect(!after.isEmpty)
        #expect(after.allSatisfy { local($0.date, "Africa/Addis_Ababa").hasSuffix(":00") && $0.zoneID == "Africa/Addis_Ababa" })
    }

    @Test("Labels never overlap, at normal and large text sizes and tight spacing", arguments: Scenarios.all.map(\.0))
    func noLabelOverlap(_ name: String) {
        let s = Scenarios.all.first { $0.0 == name }!
        let pl = plan(s.1, s.2)
        for (pph, m) in [(CGFloat(40), metrics), (24, metrics), (64, LabelMetrics(timeHeight: 30, cityHeight: 26))] {
            for d in TimelineLayout.days(for: pl) {
                let ls = TimelineLayout.labels(pl, day: d, pointsPerHour: pph, metrics: m)
                for (a, b) in zip(ls, ls.dropFirst()) {
                    #expect(a.bottom + m.gap <= b.top + 0.001, "\(name) labels overlap at \(pph) pt/h")
                }
                // Every flight event keeps a label.
                let events = TimelineLayout.flightEvents(pl.trip, in: d.span)
                #expect(ls.filter { if case .event = $0.kind { true } else { false } }.count == events.count)
            }
        }
    }

    @Test("Hour labels near a flight timestamp are suppressed")
    func hourSuppression() {
        let pl = plan(trip)
        let d23 = TimelineLayout.days(for: pl).first { $0.day == 23 }!
        let labels = TimelineLayout.labels(pl, day: d23, pointsPerHour: 40, metrics: metrics)
        // 14:30 takeoff: 14:00 and 15:00 are 20 pt away, label half-heights 7 + 7 + gap → they fit;
        // the 21:00 Namibia-equivalent hour right at the 21:20 Addis landing does not.
        #expect(!labels.contains { $0.kind == .hour && abs($0.date.timeIntervalSince(trip.segments[0].arrival)) < 15 * 60 })
    }

    @Test("Hour ticks are on the local hour across DST and fractional offsets")
    func ticks() {
        let ktm = Scenarios.fractional
        let pl = plan(ktm.0, ktm.1)
        for d in TimelineLayout.days(for: pl) {
            for t in TimelineLayout.hourTicks(pl.trip, in: d.span) {
                #expect(local(t, pl.trip.clockZoneID(at: t)).hasSuffix(":00"))
            }
        }
        let dst = plan(Scenarios.dst.0, Scenarios.dst.1)
        let fallBack = TimelineLayout.days(for: dst).first { $0.month == 11 && $0.day == 1 }
        if let fallBack { #expect(fallBack.span.duration == 25 * 3600) }
    }

    @Test("A takeoff just after midnight keeps its exact position and carries the location name")
    func eventNearDayStart() {
        let pl = plan(trip)
        let d24 = TimelineLayout.days(for: pl).first { $0.day == 24 }!
        let labels = TimelineLayout.labels(pl, day: d24, pointsPerHour: 40, metrics: LabelMetrics(timeHeight: 15, cityHeight: 24))
        let takeoff = labels.first { $0.kind == .event(.takeoff) }!
        #expect(takeoff.y == CGFloat(trip.segments[1].departure.timeIntervalSince(d24.span.start) / 3600) * 40)
        #expect(takeoff.city == "Addis Ababa")
        #expect(!labels.contains { $0.kind == .dayStart })
    }
}
