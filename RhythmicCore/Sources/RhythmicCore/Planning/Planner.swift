import Foundation

/// Deterministic rule-based planner. Same trip + preferences + rule version ⇒ identical plan.
/// No runtime language model is involved in generating schedules.
public struct Planner: Sendable {
    public var params: RuleParameters

    public init(params: RuleParameters = .current) { self.params = params }

    // MARK: - Entry point

    /// - Parameter returnDeparture: departure of the next imported trip back home, if known
    ///   (used to detect short stays that CDC suggests not adapting to).
    public func makePlan(trip: Trip, preferences p: Preferences, returnDeparture: Date? = nil) -> PlanResult {
        guard !trip.segments.isEmpty else { return .unsupported(reason: "The trip has no flights.") }
        for s in trip.segments {
            if s.status == .cancelled { return .unsupported(reason: "\(s.displayFlight) is cancelled. Review your itinerary.") }
            if s.arrival <= s.departure { return .unsupported(reason: "\(s.displayFlight) arrives before it departs. Check the times and time zones.") }
        }
        for (a, b) in zip(trip.segments, trip.segments.dropFirst()) where b.departure < a.arrival {
            return .unsupported(reason: "\(b.displayFlight) departs before \(a.displayFlight) lands. Check your itinerary.")
        }
        if let r = returnDeparture, r.timeIntervalSince(trip.arrival) < params.shortStayDays * 86400 {
            return .unsupported(reason: "This is a short stay (under \(Int(params.shortStayDays)) days). CDC guidance suggests staying on home time for trips this short. Rhythmic v1 doesn't build that kind of plan yet.")
        }
        if p.sleepHours < 4 || p.sleepHours > 12 {
            return .unsupported(reason: "Your usual sleep schedule is outside what v1 supports (4–12 hours).")
        }
        return .plan(Builder(trip: trip, prefs: p, params: params).build())
    }
}

// MARK: - Builder

private struct Builder {
    let trip: Trip
    let prefs: Preferences
    let params: RuleParameters

    let H: String          // departure zone: the body clock is assumed settled where the trip starts
    let D: String          // destination zone
    let L: Double          // habitual sleep length, hours
    let strategy: PlanStrategy
    let sign: Double       // +1 advance (body must run earlier), -1 delay, 0 none
    let target: Double     // signed phase target, hours
    let step: Double       // pre-travel shift per night, hours
    let horizon: TimeSpan
    let depDayStart: Date  // local midnight (departure zone) of departure day
    var warnings: [PlanWarning] = []

    init(trip: Trip, prefs: Preferences, params: RuleParameters) {
        self.trip = trip; self.prefs = prefs; self.params = params
        H = trip.originZoneID
        D = trip.destinationZoneID
        L = prefs.sleepHours

        var delta = Zone.offsetHours(D, at: trip.arrival) - Zone.offsetHours(H, at: trip.arrival)
        while delta > 12 { delta -= 24 }
        while delta <= -12 { delta += 24 }

        var direction = ShiftDirection.none
        var shift = 0.0
        if abs(delta) >= params.smallChangeThreshold {
            let east = delta > 0 ? delta : 24 + delta          // hours to advance
            let west = delta > 0 ? 24 - delta : -delta         // hours to delay
            let advanceDays = east / params.advanceRatePerDay
            let delayDays = west / params.delayRatePerDay
            if advanceDays <= delayDays { direction = .advance; shift = east } else { direction = .delay; shift = west }
        }
        sign = direction == .advance ? 1 : direction == .delay ? -1 : 0
        target = sign * shift
        step = direction == .none ? 0 : prefs.preTravelShift.minutesPerDay / 60

        depDayStart = Zone.startOfLocalDay(trip.departure, H)
        let start = Zone.startOfLocalDay(trip.departure, H, addingDays: -params.preparationDays)
        let end = Zone.startOfLocalDay(trip.arrival, D, addingDays: params.postArrivalDays + 1)
        horizon = TimeSpan(start, end)

        strategy = PlanStrategy(zoneDifferenceHours: delta, direction: direction, shiftHours: shift, estimatedResidualAtEndHours: 0)

        if shift >= params.largeShiftWarning {
            warnings.append(.init(severity: .caution, message: "This is a very large time change (\(Self.fmtH(shift)) h). The plan's direction is chosen by a rule of thumb, so treat it as less certain."))
        }
        if direction == .none {
            warnings.append(.init(severity: .info, message: "The time difference is small, so the plan simply follows local time."))
        }
    }

    // MARK: Phase model (rules C1, C2, P1)

    /// Number of pre-travel nights shifted by `date` (shift applied at each shifted bedtime).
    func preShiftNights(startedBy date: Date) -> Int {
        guard step > 0 else { return 0 }
        var n = 0
        for k in 1...params.preparationDays {
            // Night k starts on the evening of (departure day − (preparationDays − k + 1)).
            let nightDay = Zone.startOfLocalDay(depDayStart, H, addingDays: -(params.preparationDays - k + 1))
            let bed = homeBedtime(on: nightDay, shiftedNights: k)
            if date >= bed { n = k }
        }
        return n
    }

    func preShiftHours(nights n: Int) -> Double { min(Double(n) * step, abs(target)) }

    /// Estimated body-clock offset (hours) relative to departure-zone time. Positive = running earlier.
    func phase(at t: Date) -> Double {
        if t < trip.departure { return sign * preShiftHours(nights: preShiftNights(startedBy: t)) }
        let atDeparture = sign * preShiftHours(nights: preShiftNights(startedBy: trip.departure))
        if t < trip.arrival { return atDeparture }
        let rate = sign > 0 ? params.advanceRatePerDay : params.delayRatePerDay
        let moved = atDeparture + sign * rate * t.timeIntervalSince(trip.arrival) / 86400
        return sign >= 0 ? min(moved, target) : max(moved, target)
    }

    func residual(at t: Date) -> Double { abs(target - phase(at: t)) }

    // MARK: Helpers

    func homeBedtime(on day: Date, shiftedNights n: Int) -> Date {
        let (y, m, d) = Zone.localDay(day, H)
        let base = Zone.instant(year: y, month: m, day: d, minutesSinceMidnight: Double(prefs.bedtime.minutesSinceMidnight), zoneID: H)
        let shifted = base.adding(hours: -sign * preShiftHours(nights: n))
        // Bedtimes after midnight (e.g. 00:30) belong to the next calendar day.
        return prefs.bedtime.hour < 12 ? shifted.adding(hours: 24) : shifted
    }

    func localInstant(_ day: Date, _ zoneID: String, minutes: Double) -> Date {
        let (y, m, d) = Zone.localDay(day, zoneID)
        return Zone.instant(year: y, month: m, day: d, minutesSinceMidnight: minutes, zoneID: zoneID)
    }

    static func round15(_ d: Date) -> Date { Date(timeIntervalSince1970: (d.timeIntervalSince1970 / 900).rounded() * 900) }

    static func fmtH(_ h: Double) -> String { h == h.rounded() ? String(Int(h)) : String(format: "%.1f", h) }

    // MARK: - Sleep (rules P1, Z1, Z2, Z3)

    struct SleepPiece { var span: TimeSpan; var segmentID: String?; var note: String; var rules: [String] }

    func preTravelSleeps() -> [SleepPiece] {
        let latestEnd = trip.departure.adding(hours: -params.airportBufferHours)
        var out: [SleepPiece] = []
        for back in stride(from: params.preparationDays + 1, through: 0, by: -1) {
            let day = Zone.startOfLocalDay(depDayStart, H, addingDays: -back)
            let n = max(0, params.preparationDays + 1 - back)
            let start = homeBedtime(on: day, shiftedNights: n)
            let full = TimeSpan(start, start.adding(hours: L))
            guard full.start < latestEnd else { continue }
            let clipped = TimeSpan(full.start, min(full.end, latestEnd))
            guard clipped.duration >= 2 * 3600 else { continue }
            var note = n > 0 && step > 0
                ? (sign > 0 ? "Bedtime moved \(Self.minutes(preShiftHours(nights: n))) earlier, same sleep length." : "Bedtime moved \(Self.minutes(preShiftHours(nights: n))) later, same sleep length.")
                : "Your usual sleep."
            if clipped.end < full.end { note = "Shortened so you can get to the airport." }
            out.append(SleepPiece(span: clipped, segmentID: nil, note: note, rules: n > 0 ? ["P1", "Z3"] : ["Z3"]))
        }
        return out
    }

    /// Destination-leaning night starting on local evening `day` in zone `zoneID` (rule Z1).
    func destinationNight(on day: Date) -> TimeSpan {
        let nominal = localInstant(day, D, minutes: Double(prefs.bedtime.minutesSinceMidnight)).adding(hours: prefs.bedtime.hour < 12 ? 24 : 0)
        let allowance = sign > 0 ? params.advanceSleepAllowance : params.delaySleepAllowance
        let offset = (max(0, residual(at: nominal) - allowance) * 4).rounded() / 4   // 15-min steps; avoid false precision
        let start = nominal.adding(hours: sign * offset)   // advance → later; delay → earlier
        return TimeSpan(start, start.adding(hours: L))
    }

    func destinationSleeps() -> [SleepPiece] {
        let earliest = trip.arrival.adding(hours: params.arrivalBufferHours)
        var out: [SleepPiece] = []
        var day = Zone.startOfLocalDay(trip.arrival, D, addingDays: -1)
        let lastDay = Zone.startOfLocalDay(horizon.end, D, addingDays: 1)
        while day <= lastDay {
            let night = destinationNight(on: day)
            if night.start >= earliest {
                let shifted = abs(night.start.timeIntervalSince(localInstant(day, D, minutes: Double(prefs.bedtime.minutesSinceMidnight)).adding(hours: prefs.bedtime.hour < 12 ? 24 : 0))) > 60
                out.append(SleepPiece(span: night, segmentID: nil,
                                      note: shifted ? "Bedtime moves toward local time step by step." : "Your usual sleep, on local time.",
                                      rules: shifted ? ["Z1", "C2"] : ["Z1"]))
            }
            day = Zone.startOfLocalDay(day, D, addingDays: 1)
        }
        return out
    }

    /// Times inside the travel window where main sleep is physically feasible.
    func feasibleTravelZones() -> [(TimeSpan, String?)] {
        var zones: [(TimeSpan, String?)] = []
        for (i, s) in trip.segments.enumerated() {
            let usable = TimeSpan(s.departure.adding(minutes: params.flightSettleMinutes), s.arrival.adding(minutes: -params.flightDescentMinutes))
            if !usable.isEmpty { zones.append((usable, s.id)) }
            if i + 1 < trip.segments.count {
                let layover = TimeSpan(s.arrival.adding(hours: params.arrivalBufferHours), trip.segments[i + 1].departure.adding(hours: -params.airportBufferHours))
                if layover.duration >= 4 * 3600 { zones.append((layover, nil)) }  // long layover: hotel/lounge
            }
        }
        return zones
    }

    /// Body-night windows (habitual sleep at the estimated body clock) around the trip.
    func bodyNights(extendedEarly early: Double, late: Double) -> [TimeSpan] {
        var out: [TimeSpan] = []
        for back in -2...3 {
            let day = Zone.startOfLocalDay(depDayStart, H, addingDays: back)
            let base = localInstant(day, H, minutes: Double(prefs.bedtime.minutesSinceMidnight)).adding(hours: prefs.bedtime.hour < 12 ? 24 : 0)
            let start = base.adding(hours: -phase(at: base.adding(hours: L / 2)))
            out.append(TimeSpan(start.adding(hours: -early), start.adding(hours: L + late)))
        }
        return out
    }

    func travelSleeps() -> [SleepPiece] {
        let zones = feasibleTravelZones()
        let bodyExt = bodyNights(extendedEarly: 1, late: params.bodyNightLateExtensionHours)
        var allowed: [TimeSpan] = bodyExt
        var rules = ["Z2", "C1"]
        if !prefs.rarelySleepsOnDaytimeFlights {
            // Without the preference, destination-night sleep on any flight is also acceptable.
            var day = Zone.startOfLocalDay(trip.departure, D, addingDays: -1)
            while day <= Zone.startOfLocalDay(trip.arrival, D) {
                allowed.append(destinationNight(on: day))
                day = Zone.startOfLocalDay(day, D, addingDays: 1)
            }
            rules = ["Z1"]
        }
        var pieces: [SleepPiece] = []
        for (zone, segID) in zones {
            var candidates: [TimeSpan] = []
            for a in allowed { if let x = zone.intersection(a) { candidates.append(x) } }
            // Merge overlapping candidates within this zone.
            for c in mergeSpans(candidates) where c.duration >= 45 * 60 {
                let capped = TimeSpan(c.start, min(c.end, c.start.adding(hours: L)))
                let note = segID != nil
                    ? (capped.duration < (L - 0.5) * 3600 ? "Sleep on this flight. It's shorter than usual, so rest when you can after you land." : "Sleep on this flight.")
                    : "Sleep during your layover if you can get a bed or quiet space."
                pieces.append(SleepPiece(span: capped, segmentID: segID, note: note, rules: rules + ["Z3"]))
            }
        }
        return pieces
    }

    func mergeSpans(_ spans: [TimeSpan]) -> [TimeSpan] {
        let sorted = spans.sorted { $0.start < $1.start }
        var out: [TimeSpan] = []
        for s in sorted {
            if let last = out.last, s.start <= last.end { out[out.count - 1] = TimeSpan(last.start, max(last.end, s.end)) }
            else { out.append(s) }
        }
        return out
    }

    // MARK: - Build

    func build() -> Plan {
        var blocks: [PlanBlock] = []
        var b = self

        // Sleep
        var sleeps = preTravelSleeps() + travelSleeps() + destinationSleeps()
        sleeps.sort { $0.span.start < $1.span.start }
        // Defensive: drop any piece overlapping an earlier one (keeps invariants simple).
        var nonOverlapping: [SleepPiece] = []
        for s in sleeps where !(nonOverlapping.last.map { $0.span.overlaps(s.span) } ?? false) { nonOverlapping.append(s) }
        sleeps = nonOverlapping
        let sleepSpans = sleeps.map(\.span)

        // Light windows (rules C1, L1, L2, L3)
        let circadian = lightWindows()
        let windDowns = sleeps.filter { $0.segmentID == nil }.map { TimeSpan($0.span.start.adding(hours: -params.windDownHours), $0.span.start) }
        // Priority: sleep > circadian reduce > prioritise > wind-down > helpful.
        let reduceSpans = mergeSpans(circadian.filter { $0.kind == .reduceLight }.flatMap { $0.span.subtracting(sleepSpans) })
        let prioritizeSpans = mergeSpans(circadian.filter { $0.kind == .prioritizeLight }.flatMap { $0.span.subtracting(sleepSpans + reduceSpans) })
        let windDownSpans = mergeSpans(windDowns.flatMap { $0.subtracting(sleepSpans + reduceSpans + prioritizeSpans) })
        let helpfulSpans = mergeSpans(circadian.filter { $0.kind == .lightHelpful }.flatMap { $0.span.subtracting(sleepSpans + reduceSpans + prioritizeSpans + windDownSpans) })

        // Naps (rule N1) — avoid prioritise-light windows and airport logistics.
        let naps = napWindows(sleeps: sleepSpans, avoid: prioritizeSpans)

        for s in sleeps {
            blocks.append(block(.sleep, s.span, title: "Sleep", detail: s.note, rules: s.rules, segmentID: s.segmentID))
        }
        for n in naps {
            blocks.append(block(.nap, n, title: "Optional nap", detail: "A short nap of 20–30 min, any time in this window, if you need it. The window isn't a sleep length.", minutes: 20...30, optional: true, rules: ["N1"], segmentID: trip.segment(airborneAt: n.start)?.id))
        }
        for r in reduceSpans {
            let seg = trip.segment(airborneAt: r.start)
            blocks.append(block(.reduceLight, r, title: "Keep light low",
                                detail: seg != nil ? "Window shade down, use an eye mask, keep screens dim." : "Dim the lights. Outdoors, sunglasses help, but not while driving.",
                                rules: ["L1", "C1"], segmentID: seg?.id))
        }
        for w in windDownSpans {
            blocks.append(block(.reduceLight, w, title: "Wind down", detail: "Dim the lights and slow down before bed.", rules: ["L3"]))
        }
        for p in prioritizeSpans { blocks += b.lightBlocks(.prioritizeLight, p) }
        for h in helpfulSpans { blocks += b.lightBlocks(.lightHelpful, h) }

        // Caffeine (rules K1, K2, K3)
        if prefs.caffeine != .none { blocks += caffeineBlocks(sleeps: sleepSpans, naps: naps) }

        // Flights (context)
        for s in trip.segments {
            blocks.append(PlanBlock(id: "flight-\(s.id)", kind: .flight, start: s.departure, end: s.arrival,
                                    title: s.flightNumber != nil ? "\(s.displayFlight) · \(s.origin) → \(s.destination)" : "\(s.origin) → \(s.destination)",
                                    detail: "Flight", recommendedMinutes: nil, isOptional: false, ruleIDs: [],
                                    zoneID: s.originZoneID, segmentID: s.id))
        }

        // Clip to horizon and sort deterministically.
        blocks = blocks.compactMap { blk in
            guard blk.kind != .flight else { return blk }
            guard let c = blk.span.intersection(horizon) else { return nil }
            var x = blk; x.start = c.start; x.end = c.end; return x
        }
        blocks.sort { ($0.start, $0.kind.rawValue, $0.end) < ($1.start, $1.kind.rawValue, $1.end) }

        var strat = strategy
        strat.estimatedResidualAtEndHours = (residual(at: horizon.end) * 10).rounded() / 10
        if strat.direction != .none && strat.estimatedResidualAtEndHours >= 0.5 {
            b.warnings.append(.init(severity: .info, message: "This plan covers \(params.postArrivalDays) days after arrival. Using population averages, your body clock may still be about \(Self.fmtH(strat.estimatedResidualAtEndHours)) h from local time when it ends. Keep regular local sleep times and get morning daylight."))
        }

        let id = Self.planID(trip: trip, prefs: prefs)
        return Plan(id: id, ruleVersion: RuleBook.version, tripID: trip.id, tripFingerprint: trip.fingerprint,
                    preferences: prefs, trip: trip, horizon: horizon, strategy: strat, blocks: blocks, warnings: b.warnings)
    }

    func block(_ kind: BlockKind, _ span: TimeSpan, title: String, detail: String, minutes: ClosedRange<Int>? = nil,
               optional: Bool = false, rules: [String], segmentID: String? = nil) -> PlanBlock {
        PlanBlock(id: "\(kind.rawValue)-\(Int(span.start.timeIntervalSince1970))", kind: kind, start: span.start, end: span.end,
                  title: title, detail: detail, recommendedMinutes: minutes, isOptional: optional, ruleIDs: rules,
                  zoneID: trip.zoneID(at: span.start), segmentID: segmentID)
    }

    // MARK: Light

    struct RawLight { var kind: BlockKind; var span: TimeSpan }

    func lightWindows() -> [RawLight] {
        guard sign != 0 else { return [] }
        var out: [RawLight] = []
        var day = Zone.startOfLocalDay(horizon.start, H, addingDays: -1)
        let last = horizon.end.adding(hours: 24)
        while day < last {
            let nominal = localInstant(day, H, minutes: Double(prefs.wakeTime.minutesSinceMidnight) - params.tminHoursBeforeWake * 60)
            var t = nominal
            for _ in 0..<3 { t = nominal.adding(hours: -phase(at: t)) }   // fixed-point: Tmin moves with the clock
            t = Self.round15(t)
            if sign > 0 {
                out.append(RawLight(kind: .reduceLight, span: TimeSpan(t.adding(hours: -4), t)))
                out.append(RawLight(kind: .prioritizeLight, span: TimeSpan(t, t.adding(hours: 5))))
                out.append(RawLight(kind: .lightHelpful, span: TimeSpan(t.adding(hours: 5), t.adding(hours: 8))))
            } else {
                out.append(RawLight(kind: .lightHelpful, span: TimeSpan(t.adding(hours: -8), t.adding(hours: -5))))
                out.append(RawLight(kind: .prioritizeLight, span: TimeSpan(t.adding(hours: -5), t)))
                out.append(RawLight(kind: .reduceLight, span: TimeSpan(t, t.adding(hours: 4))))
            }
            day = Zone.startOfLocalDay(day, H, addingDays: 1)
        }
        return out
    }

    mutating func lightBlocks(_ kind: BlockKind, _ span: TimeSpan) -> [PlanBlock] {
        if let seg = trip.segment(airborneAt: span.start) {
            return [block(kind, span, title: kind == .prioritizeLight ? "Seek light" : "Light helpful",
                          detail: "Open the window shade if it's light outside, and use the reading light.", minutes: kind == .prioritizeLight ? 30...60 : nil,
                          optional: kind == .lightHelpful, rules: ["L1", "L2"], segmentID: seg.id)]
        }
        let zone = trip.zoneID(at: span.start)
        let place = (span.start < trip.departure ? Airports.lookup(trip.first.origin) : nil)
            ?? Airports.lookup(trip.segments.last(where: { $0.arrival <= span.start })?.destination)
            ?? Airports.representative(forZone: zone)
        guard let place else {
            return [block(kind, span, title: kind == .prioritizeLight ? "Bright light" : "Light helpful", detail: "Bright light helps now.", rules: ["L1"])]
        }
        return Solar.splitByDaylight(span, latitude: place.latitude, longitude: place.longitude).map { piece, day in
            switch (kind, day) {
            case (.prioritizeLight, true):
                return block(kind, piece, title: "Get daylight", detail: "Try to spend 30–60 min outside in this window. Don't look directly at the sun.", minutes: 30...60, rules: ["L1", "L2"])
            case (.prioritizeLight, false):
                return block(kind, piece, title: "Bright light", detail: "The sun isn't up yet. Turn on bright indoor lights; a phone screen isn't enough.", minutes: 30...60, rules: ["L1", "L2"])
            case (_, true):
                return block(kind, piece, title: "Light helpful", detail: "Daylight now also helps. Optional.", optional: true, rules: ["L1", "L2"])
            default:
                return block(kind, piece, title: "Light helpful", detail: "Ordinary bright indoor light is fine. Optional.", optional: true, rules: ["L1", "L2"])
            }
        }
    }

    // MARK: Naps

    func napWindows(sleeps: [TimeSpan], avoid: [TimeSpan]) -> [TimeSpan] {
        var logistics: [TimeSpan] = []
        for s in trip.segments {
            logistics.append(TimeSpan(s.departure.adding(hours: -params.airportBufferHours), s.departure.adding(minutes: params.flightSettleMinutes)))
            logistics.append(TimeSpan(s.arrival.adding(minutes: -params.flightDescentMinutes), s.arrival.adding(hours: params.arrivalBufferHours)))
        }
        var out: [TimeSpan] = []
        for (a, b) in zip(sleeps, sleeps.dropFirst()) {
            let awake = TimeSpan(a.end, b.start)
            // Only offer naps on days notably longer than usual (habitual wake span + margin).
            let threshold = max(params.napAwakeThresholdHours, 24 - L + params.napExtraAwakeHours)
            guard awake.duration >= threshold * 3600 else { continue }
            let allowedSpan = TimeSpan(a.end.adding(hours: 6), b.start.adding(hours: -params.napMinGapBeforeSleepHours))
            guard !allowedSpan.isEmpty else { continue }
            let pieces = allowedSpan.subtracting(logistics + avoid)
            guard let best = pieces.max(by: { $0.duration < $1.duration }), best.duration >= 30 * 60 else { continue }
            // Latest part of the allowed range: most useful on long travel days, still ≥ 5 h before sleep.
            out.append(TimeSpan(max(best.start, best.end.adding(hours: -params.napWindowMaxHours)), best.end))
        }
        return out
    }

    // MARK: Caffeine

    func caffeineBlocks(sleeps: [TimeSpan], naps: [TimeSpan]) -> [PlanBlock] {
        var out: [PlanBlock] = []
        let cutoffH = prefs.caffeineSensitive ? params.caffeineCutoffSensitiveHours : params.caffeineCutoffHours
        for (a, b) in zip(sleeps, sleeps.dropFirst()) {
            let awake = TimeSpan(a.end, b.start)
            let cutoff = b.start.adding(hours: -cutoffH)
            if cutoff > awake.start {
                let napHoles = naps.map { TimeSpan($0.start.adding(hours: -params.caffeineBeforeNapHours), $0.end) }
                for ok in TimeSpan(awake.start, cutoff).subtracting(napHoles) where ok.duration >= 30 * 60 {
                    out.append(block(.caffeineOK, ok, title: "Caffeine OK",
                                     detail: "If you want it: your usual amount, earlier rather than later. This isn't a cue to keep drinking.",
                                     optional: true, rules: ["K1", "K2"], segmentID: trip.segment(airborneAt: ok.start)?.id))
                }
            }
            let avoid = TimeSpan(max(cutoff, awake.start), awake.end)
            if avoid.duration >= 30 * 60 {
                out.append(block(.caffeineAvoid, avoid, title: "No caffeine",
                                 detail: "Skip coffee, tea, cola and energy drinks to protect your next sleep.",
                                 rules: ["K1", "K3"], segmentID: trip.segment(airborneAt: avoid.start)?.id))
            }
        }
        return out
    }

    static func minutes(_ h: Double) -> String {
        let m = Int((h * 60).rounded())
        return m % 60 == 0 ? "\(m / 60) h" : (m < 60 ? "\(m) min" : "\(m / 60) h \(m % 60) min")
    }

    // MARK: Determinism

    static func planID(trip: Trip, prefs: Preferences) -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        enc.dateEncodingStrategy = .secondsSince1970
        var data = (try? enc.encode(trip)) ?? Data()
        data += (try? enc.encode(prefs)) ?? Data()
        data += Data(RuleBook.version.utf8)
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in data { hash ^= UInt64(byte); hash &*= 0x100000001b3 }
        return String(hash, radix: 16)
    }
}
