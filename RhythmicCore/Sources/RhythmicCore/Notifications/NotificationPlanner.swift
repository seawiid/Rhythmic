import Foundation

/// Converts a plan into a small set of reminders at meaningful transitions.
/// Platform-neutral: the iOS layer only schedules what this returns.
///
/// Rules:
/// - One reminder per transition, never repeated through a window.
/// - Reminders within `mergeWindow` of each other are combined into one.
/// - Optional nudges (naps, "light helpful", caffeine-OK) never notify.
/// - Nothing fires during planned main sleep except the sleep transition itself.
/// - Wake reminders are ordinary notifications, NOT alarms.
public struct NotificationPlanner: Sendable {
    public var mergeWindow: TimeInterval = 15 * 60
    public var bedtimeLead: TimeInterval = 30 * 60
    public var caffeineLead: TimeInterval = 30 * 60
    /// iOS keeps at most 64 pending local notifications per app; we stay below it.
    public static let iosPendingLimit = 60

    public init() {}

    struct Raw { var date: Date; var priority: Int; var title: String; var body: String; var isSleepEdge: Bool }

    public func transitions(for plan: Plan) -> [PlanTransition] {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        fmt.locale = Locale(identifier: "en_GB")
        func time(_ d: Date) -> String {
            fmt.timeZone = TimeZone(identifier: plan.trip.zoneID(at: d))
            return fmt.string(from: d)
        }
        // A phone's clock zone is unreliable while airborne, so in-flight texts use durations.
        func until(_ end: Date, from start: Date) -> String {
            if plan.trip.segment(airborneAt: start) != nil || plan.trip.segment(airborneAt: end) != nil {
                return "for about \(Self.duration(end.timeIntervalSince(start)))"
            }
            return "until \(time(end))"
        }

        var raw: [Raw] = []
        let sleeps = plan.blocks.filter { $0.kind == .sleep }
        for s in sleeps {
            if s.segmentID == nil {
                raw.append(Raw(date: s.start.addingTimeInterval(-bedtimeLead), priority: 2, title: "Bedtime in 30 minutes",
                               body: "Dim the lights and start winding down.", isSleepEdge: false))
            }
            if s.start > plan.horizon.start {   // a sleep already underway when the plan starts has no bedtime
                let untilText = s.end >= plan.horizon.end ? "This is the last night of your plan." : "Sleep \(until(s.end, from: s.start))."
                raw.append(Raw(date: s.start, priority: 3, title: "Time to sleep",
                               body: s.segmentID != nil ? (s.end >= plan.horizon.end ? "Sleep on this flight." : "Sleep window on this flight: about \(Self.duration(s.end.timeIntervalSince(s.start))).") : "Lights out. \(untilText)",
                               isSleepEdge: true))
            }
            // A sleep that ends because the plan horizon ends isn't a real wake transition.
            if s.end < plan.horizon.end {
                raw.append(Raw(date: s.end, priority: 3, title: "Time to start your day",
                               body: "Planned wake time. This is a reminder, not an alarm.", isSleepEdge: true))
            }
        }

        // Light: notify at the start of each contiguous prioritise / circadian-reduce run.
        let light = plan.blocks.filter { $0.kind == .prioritizeLight || ($0.kind == .reduceLight && $0.ruleIDs.contains("L1")) }
        var previous: PlanBlock?
        for b in light {
            let continues = previous.map { $0.kind == b.kind && abs($0.end.timeIntervalSince(b.start)) < 60 } ?? false
            previous = b
            if continues { continue }
            if b.kind == .prioritizeLight {
                let title = b.title == "Get daylight" ? "Time for daylight" : (b.segmentID != nil ? "Seek light now" : "Time for bright light")
                raw.append(Raw(date: b.start, priority: 1, title: title, body: "Window open \(until(b.end, from: b.start)). Aim for 30–60 min.", isSleepEdge: false))
            } else {
                raw.append(Raw(date: b.start, priority: 1, title: "Keep lights low now",
                               body: b.segmentID != nil ? "Shade down or eye mask \(until(b.end, from: b.start))." : "Dim light \(until(b.end, from: b.start)).", isSleepEdge: false))
            }
        }

        if plan.preferences.caffeine != .none {
            for c in plan.blocks where c.kind == .caffeineAvoid {
                // Warn before the end of the last permitted window that precedes this cutoff (same waking day).
                guard let lastOK = plan.blocks.last(where: { $0.kind == .caffeineOK && $0.end <= c.start && c.start.timeIntervalSince($0.end) < 6 * 3600 }) else { continue }
                raw.append(Raw(date: lastOK.end.addingTimeInterval(-caffeineLead), priority: 1, title: "Coffee cutoff approaching",
                               body: "Last caffeine in 30 minutes.", isSleepEdge: false))
            }
        }

        // Suppress anything during main sleep (other than the sleep edges themselves).
        raw = raw.filter { r in r.isSleepEdge || !sleeps.contains { $0.span.contains(r.date) } }
        raw = raw.filter { plan.horizon.contains($0.date) }
        raw.sort { ($0.date, -$0.priority, $0.title) < ($1.date, -$1.priority, $1.title) }

        // Combine reminders that are close together into one.
        var merged: [Raw] = []
        for r in raw {
            if var last = merged.last, r.date.timeIntervalSince(last.date) <= mergeWindow, !(last.isSleepEdge && r.isSleepEdge) {
                if r.priority > last.priority {
                    last = Raw(date: last.date, priority: r.priority, title: r.title, body: r.body + " " + last.title + ".", isSleepEdge: r.isSleepEdge)
                } else {
                    last.body += " " + r.title + "."
                }
                merged[merged.count - 1] = last
            } else {
                merged.append(r)
            }
        }

        return merged.map { r in
            PlanTransition(id: "rhythmic.\(plan.id).\(Int(r.date.timeIntervalSince1970))", date: r.date, title: r.title, body: r.body)
        }
    }

    static func duration(_ t: TimeInterval) -> String {
        let m = Int((t / 60 / 15).rounded()) * 15
        return m < 60 ? "\(m) min" : (m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(m % 60) min")
    }

    /// What to hand to the OS now: future reminders only, earliest first, capped below the iOS limit.
    public func pending(for plan: Plan, now: Date, enabled: Bool) -> [PlanTransition] {
        guard enabled, now < plan.horizon.end else { return [] }
        return Array(transitions(for: plan).filter { $0.date > now }.prefix(Self.iosPendingLimit))
    }
}
