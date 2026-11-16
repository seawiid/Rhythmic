import Foundation
import Testing
@testable import RhythmicCore

@Suite("Notifications")
struct NotificationTests {
    let planner = NotificationPlanner()

    @Test("Nothing fires during planned main sleep except the sleep edges", arguments: Scenarios.all.map(\.0))
    func quietDuringSleep(_ name: String) {
        let s = Scenarios.all.first { $0.0 == name }!
        let pl = plan(s.1, s.2)
        let sleeps = pl.blocks.filter { $0.kind == .sleep }
        for n in planner.transitions(for: pl) where n.title != "Time to sleep" {
            #expect(!sleeps.contains { $0.span.contains(n.date) }, "\(n.title) at \(n.date) during sleep")
        }
    }

    @Test("Reminders are combined: none within 15 minutes of each other, except sleep/wake pairs", arguments: Scenarios.all.map(\.0))
    func combined(_ name: String) {
        let s = Scenarios.all.first { $0.0 == name }!
        let ts = planner.transitions(for: plan(s.1, s.2))
        for (a, b) in zip(ts, ts.dropFirst()) {
            #expect(b.date > a.date)
            #expect(b.date.timeIntervalSince(a.date) > 15 * 60 || (a.title.hasPrefix("Time to") && b.title.hasPrefix("Time to")))
        }
        #expect(Set(ts.map(\.id)).count == ts.count)
    }

    @Test("Optional nudges (naps, light helpful, caffeine OK) never notify")
    func noOptionalNudges() {
        let ts = planner.transitions(for: plan(Fixtures.namibiaSingapore))
        #expect(!ts.contains { $0.title.localizedCaseInsensitiveContains("nap") || $0.title.contains("helpful") })
    }

    @Test("Wake reminders say they are not alarms")
    func notAlarm() {
        let ts = planner.transitions(for: plan(Fixtures.namibiaSingapore))
        let wakes = ts.filter { $0.title == "Time to start your day" }
        #expect(!wakes.isEmpty)
        #expect(wakes.allSatisfy { $0.body.contains("not an alarm") })
    }

    @Test("Non-caffeine users get no caffeine reminders")
    func noCaffeineReminders() {
        let ts = planner.transitions(for: plan(Scenarios.noCaffeine.0, Scenarios.noCaffeine.1))
        #expect(!ts.contains { $0.title.contains("Coffee") })
        let users = planner.transitions(for: plan(Fixtures.namibiaSingapore))
        #expect(users.contains { $0.title == "Coffee cutoff approaching" })
    }

    @Test("Expected transition reminders appear for the demo")
    func expectedKinds() {
        let titles = Set(planner.transitions(for: plan(Fixtures.namibiaSingapore)).map(\.title))
        for t in ["Time to sleep", "Time to start your day", "Bedtime in 30 minutes", "Keep lights low now", "Coffee cutoff approaching"] {
            #expect(titles.contains(t), "missing \(t)")
        }
    }

    @Test("Only future reminders are scheduled; none after the plan ends or when disabled")
    func pending() {
        let pl = plan(Fixtures.namibiaSingapore)
        let mid = pl.trip.arrival
        let now = planner.pending(for: pl, now: mid, enabled: true)
        #expect(now.allSatisfy { $0.date > mid })
        #expect(now.count <= NotificationPlanner.iosPendingLimit)
        #expect(planner.pending(for: pl, now: pl.horizon.end.addingTimeInterval(1), enabled: true).isEmpty)
        #expect(planner.pending(for: pl, now: pl.horizon.start, enabled: false).isEmpty)
    }

    @Test("Replacing a plan leaves no stale reminders")
    func noStaleAfterReplace() {
        var t = Fixtures.namibiaSingapore
        let old = plan(t)
        let oldPending = planner.pending(for: old, now: old.horizon.start, enabled: true)
        t.segments[1].arrival = t.segments[1].arrival.addingTimeInterval(2 * 3600)  // itinerary change
        let new = plan(t)
        let desired = planner.pending(for: new, now: new.horizon.start, enabled: true)

        let foreign = "someone-elses-notification"
        let diff = NotificationSync.diff(pendingIDs: oldPending.map(\.id) + [foreign], desired: desired)
        let after = Set(oldPending.map(\.id) + [foreign]).subtracting(diff.remove).union(diff.add.map(\.id))
        #expect(after.subtracting([foreign]) == Set(desired.map(\.id)))
        #expect(after.contains(foreign), "never touch notifications we don't own")
        #expect(oldPending.allSatisfy { !after.contains($0.id) })
    }

    @Test("Disabling removes all of our pending reminders")
    func disableClears() {
        let pl = plan(Fixtures.namibiaSingapore)
        let ids = planner.pending(for: pl, now: pl.horizon.start, enabled: true).map(\.id)
        let diff = NotificationSync.diff(pendingIDs: ids, desired: planner.pending(for: pl, now: pl.horizon.start, enabled: false))
        #expect(Set(diff.remove) == Set(ids))
        #expect(diff.add.isEmpty)
    }
}
