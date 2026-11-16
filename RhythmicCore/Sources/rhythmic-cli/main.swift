import Foundation
import RhythmicCore

// Developer tool: prints a plan in local + home time. `swift run rhythmic-cli [east|west] [--flights-ok]`
let args = CommandLine.arguments
let west = args.contains("west")
var prefs = west ? Fixtures.singaporeHomePrefs : Preferences.demo
if args.contains("--flights-ok") { prefs.rarelySleepsOnDaytimeFlights = false }
let trip = west ? Fixtures.singaporeUganda : Fixtures.namibiaSingapore

func fmt(_ d: Date, _ z: String) -> String {
    let f = DateFormatter(); f.timeZone = TimeZone(identifier: z); f.dateFormat = "EEE dd MMM HH:mm"; f.locale = Locale(identifier: "en_GB")
    return f.string(from: d)
}

switch Planner().makePlan(trip: trip, preferences: prefs) {
case .unsupported(let r): print("UNSUPPORTED: \(r)")
case .plan(let plan):
    print("Plan \(plan.id)  rules \(plan.ruleVersion)")
    print("Strategy: \(plan.strategy)")
    plan.warnings.forEach { print("⚠︎ \($0.message)") }
    for b in plan.blocks {
        let local = "\(fmt(b.start, b.zoneID)) → \(fmt(b.end, plan.trip.zoneID(at: b.end)))"
        let home = "\(fmt(b.start, plan.homeZoneID)) → \(fmt(b.end, plan.homeZoneID))"
        print(String(format: "%-15@ %-16@ %@  [home %@]", b.kind.rawValue as NSString, b.title as NSString, local as NSString, home as NSString))
    }
    print("\nNotifications:")
    for n in NotificationPlanner().transitions(for: plan) {
        print("  \(fmt(n.date, plan.trip.zoneID(at: n.date)))  \(n.title) — \(n.body)")
    }
}
