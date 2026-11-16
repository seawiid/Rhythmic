import Foundation
import Testing
@testable import RhythmicCore

@Suite("Planner invariants (engineering validation, not clinical validation)")
struct PlannerInvariantTests {
    static let cases = Scenarios.all.map(\.0)
    static func scenario(_ name: String) -> (Trip, Preferences) {
        let s = Scenarios.all.first { $0.0 == name }!
        return (s.1, s.2)
    }

    @Test("Deterministic: same inputs + rule version ⇒ identical plan", arguments: cases)
    func deterministic(_ name: String) {
        let (t, p) = Self.scenario(name)
        let a = plan(t, p), b = plan(t, p)
        #expect(a == b)
        #expect(a.ruleVersion == RuleBook.version)
    }

    @Test("Blocks are ordered by absolute time and inside the horizon", arguments: cases)
    func ordering(_ name: String) {
        let (t, p) = Self.scenario(name)
        let pl = plan(t, p)
        let starts = pl.blocks.map(\.start)
        #expect(starts == starts.sorted())
        for b in pl.blocks where b.kind != .flight {
            #expect(b.start >= pl.horizon.start && b.end <= pl.horizon.end, "\(b.title) outside horizon")
            #expect(b.end > b.start)
        }
    }

    @Test("No overlapping contradictory light instructions", arguments: cases)
    func lightNoOverlap(_ name: String) {
        let (t, p) = Self.scenario(name)
        let light = plan(t, p).blocks.filter { $0.kind.lane == .light }
        for (i, a) in light.enumerated() {
            for b in light[(i + 1)...] {
                #expect(!a.span.overlaps(b.span), "\(a.title) overlaps \(b.title)")
            }
        }
    }

    @Test("No light or caffeine instructions inside main sleep", arguments: cases)
    func nothingDuringSleep(_ name: String) {
        let (t, p) = Self.scenario(name)
        let pl = plan(t, p)
        let sleeps = pl.blocks.filter { $0.kind == .sleep }
        for b in pl.blocks where b.kind.lane == .light || b.kind.lane == .caffeine || b.kind == .nap {
            for s in sleeps {
                #expect(!b.span.overlaps(s.span), "\(b.title) overlaps sleep at \(s.start)")
            }
        }
    }

    @Test("Main sleeps don't overlap and keep the usual length (except at plan edges or when travel shortens them)", arguments: cases)
    func sleepShape(_ name: String) {
        let (t, p) = Self.scenario(name)
        let pl = plan(t, p)
        let sleeps = pl.blocks.filter { $0.kind == .sleep }
        for (a, b) in zip(sleeps, sleeps.dropFirst()) { #expect(a.end <= b.start) }
        for s in sleeps {
            #expect(s.span.duration <= p.sleepHours * 3600 + 1)
            let atEdge = s.start == pl.horizon.start || s.end == pl.horizon.end
            let travel = s.segmentID != nil || s.detail.contains("airport")
            if !atEdge && !travel { #expect(abs(s.span.duration - p.sleepHours * 3600) < 1, "\(s.start) sleep not full length") }
        }
    }

    @Test("No sleep block crosses a departure or landing", arguments: cases)
    func sleepVsFlights(_ name: String) {
        let (t, p) = Self.scenario(name)
        for s in plan(t, p).blocks where s.kind == .sleep {
            for f in t.segments {
                #expect(!s.span.contains(f.departure) && !s.span.contains(f.arrival), "sleep \(s.start) crosses \(f.origin)→\(f.destination)")
                if s.span.overlaps(f.span) {
                    #expect(s.segmentID == f.id)
                    #expect(s.start >= f.departure.addingTimeInterval(30 * 60) && s.end <= f.arrival.addingTimeInterval(-45 * 60))
                }
            }
        }
    }

    @Test("Ground sleep before departure ends ≥ 3 h before the flight", arguments: cases)
    func airportBuffer(_ name: String) {
        let (t, p) = Self.scenario(name)
        for s in plan(t, p).blocks where s.kind == .sleep && s.end <= t.departure {
            #expect(s.end <= t.departure.addingTimeInterval(-3 * 3600))
        }
    }

    @Test("Nap blocks are optional windows with a short recommended duration", arguments: cases)
    func napsAreWindows(_ name: String) {
        let (t, p) = Self.scenario(name)
        for n in plan(t, p).blocks where n.kind == .nap {
            #expect(n.isOptional)
            #expect(n.recommendedMinutes == 20...30)
            #expect(n.span.duration <= 3 * 3600)
        }
    }

    @Test("Caffeine never suggested to non-users; cutoff respected for users", arguments: cases)
    func caffeine(_ name: String) {
        let (t, p) = Self.scenario(name)
        let pl = plan(t, p)
        if p.caffeine == .none {
            #expect(!pl.blocks.contains { $0.kind.lane == .caffeine })
            return
        }
        let cutoff = (p.caffeineSensitive ? 10.0 : 8.0) * 3600
        let sleeps = pl.blocks.filter { $0.kind == .sleep }
        for c in pl.blocks where c.kind == .caffeineOK {
            if let next = sleeps.first(where: { $0.start >= c.end }) {
                #expect(next.start.timeIntervalSince(c.end) >= cutoff - 1, "caffeine too close to sleep at \(next.start)")
            }
            // Not right before a nap window.
            for n in pl.blocks where n.kind == .nap && n.start >= c.end {
                #expect(n.start.timeIntervalSince(c.end) >= 3600 - 1 || n.start.timeIntervalSince(c.end) > 6 * 3600)
            }
        }
    }
}

@Suite("Personalisation and scope")
struct PlannerBehaviourTests {
    @Test("Demo: horizon is 21 Nov (home) through end of 26 Nov (destination)")
    func horizon() {
        let p = plan(Fixtures.namibiaSingapore)
        #expect(local(p.horizon.start, "Africa/Windhoek") == "2026-11-21 00:00")
        #expect(local(p.horizon.end, "Asia/Singapore") == "2026-11-27 00:00")
        #expect(p.warnings.contains { $0.message.contains("may still be about") }, "must not imply full recovery")
    }

    @Test("Demo with 'rarely sleep on afternoon flights': no sleep on the afternoon WDH–ADD leg")
    func noAfternoonFlightSleep() {
        let p = plan(Fixtures.namibiaSingapore)
        let first = Fixtures.namibiaSingapore.segments[0]
        #expect(!p.blocks.contains { $0.kind == .sleep && $0.span.overlaps(first.span) })
        // The overnight ADD–SIN leg carries the travel sleep, during biological night (home time ≥ 20:00).
        let flightSleep = p.blocks.filter { $0.kind == .sleep && $0.segmentID == "sample-add-sin" }
        #expect(flightSleep.count == 1)
        let startHome = Calendar.current.dateComponents(in: TimeZone(identifier: "Africa/Windhoek")!, from: flightSleep[0].start)
        #expect(startHome.hour! >= 20 || startHome.hour! < 4)
    }

    @Test("Preference never relies on long afternoon-flight sleep; without it, more flight sleep may be planned")
    func afternoonPreference() {
        let (trip, prefs) = Scenarios.afternoonLongHaul
        let flight = trip.segments[0]
        var noPref = prefs; noPref.rarelySleepsOnDaytimeFlights = false

        func flightSleepHours(_ p: Plan) -> Double {
            p.blocks.filter { $0.kind == .sleep && $0.segmentID == flight.id }.map(\.span.duration).reduce(0, +) / 3600
        }
        let withPref = plan(trip, prefs), without = plan(trip, noPref)
        #expect(flightSleepHours(without) > flightSleepHours(withPref), "\(flightSleepHours(without)) vs \(flightSleepHours(withPref))")

        // With the preference, no flight sleep starts before ~19:00 home time (an hour before the
        // earliest shifted biological night): nothing in the biological afternoon.
        for s in withPref.blocks where s.kind == .sleep && s.segmentID == flight.id {
            let h = Calendar.current.dateComponents(in: TimeZone(identifier: prefs.homeZoneID)!, from: s.start).hour!
            #expect(h >= 19 || h < 6, "flight sleep starts at \(h):00 home time")
        }
    }

    @Test("Small time change: local-time plan, no circadian light instructions")
    func smallChange() {
        var p = Preferences.demo; p.homeZoneID = "Africa/Johannesburg"
        let trip = Trip(id: "jnb-nbo", segments: [seg("jnb-nbo", "JNB", "NBO", dep: .init(2026, 11, 23, 10, 0), arr: .init(2026, 11, 23, 15, 0))])
        let pl = plan(trip, p)
        #expect(pl.strategy.direction == .none)
        #expect(!pl.blocks.contains { $0.kind == .prioritizeLight || $0.kind == .lightHelpful })
    }

    @Test("Short stay is acknowledged as unsupported instead of planned")
    func shortStay() {
        let trip = Fixtures.namibiaSingapore
        let result = Planner().makePlan(trip: trip, preferences: .demo, returnDeparture: trip.arrival.addingTimeInterval(30 * 3600))
        guard case .unsupported(let reason) = result else { Issue.record("expected unsupported"); return }
        #expect(reason.contains("short stay"))
    }

    @Test("Cancelled or inconsistent segments are refused, not planned")
    func invalidTrips() {
        var t = Fixtures.namibiaSingapore
        t.segments[1].status = .cancelled
        if case .plan = Planner().makePlan(trip: t, preferences: .demo) { Issue.record("cancelled segment planned") }
        var u = Fixtures.namibiaSingapore
        u.segments[1].departure = u.segments[0].arrival.addingTimeInterval(-3600)
        if case .plan = Planner().makePlan(trip: u, preferences: .demo) { Issue.record("overlapping segments planned") }
    }

    @Test("Fractional-offset destination: recommendation times fall on 15-minute local boundaries")
    func fractionalBoundaries() {
        let pl = plan(Scenarios.fractional.0, Scenarios.fractional.1)
        #expect(pl.strategy.zoneDifferenceHours == 5.75)
        for b in pl.blocks where b.kind == .sleep && b.start > pl.trip.arrival {
            let m = Calendar.current.dateComponents(in: TimeZone(identifier: "Asia/Kathmandu")!, from: b.start).minute!
            #expect(m % 15 == 0)
        }
    }

    @Test("Every block cites rules that exist in the rule book")
    func ruleReferences() {
        for (_, t, p) in Scenarios.all {
            for b in plan(t, p).blocks { for r in b.ruleIDs { #expect(RuleBook.rule(r) != nil, "unknown rule \(r)") } }
        }
    }

    @Test("Changing the itinerary changes the plan id")
    func itineraryChange() {
        var t = Fixtures.namibiaSingapore
        let a = plan(t)
        t.segments[1].arrival = t.segments[1].arrival.addingTimeInterval(45 * 60)
        let b = plan(t)
        #expect(a.id != b.id)
        #expect(a.tripFingerprint != b.tripFingerprint)
    }
}
