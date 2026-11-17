import SwiftUI
import UIKit
import RhythmicCore

/// Plan tab: header with reminders bell, static route, day selector, current action, timeline.
struct PlanTab: View {
    @Environment(AppModel.self) private var model
    var showTrips: () -> Void

    var body: some View {
        if let plan = model.plan {
            PlanView(plan: plan)
        } else {
            VStack(spacing: 0) {
                PlanHeader().padding(.horizontal, 16)
                ContentUnavailableView {
                    Label("No plan yet", systemImage: "airplane.departure")
                } description: {
                    Text("Add or import your flights, then choose a trip in Trips.")
                } actions: {
                    Button("Go to Trips", action: showTrips).buttonStyle(.borderedProminent).tint(Palette.ink)
                }
                .frame(maxHeight: .infinity)
            }
            .background(Palette.background)
        }
    }
}

struct PlanHeader: View {
    var body: some View {
        HStack {
            Text("Rhythmic").font(.title2.weight(.semibold)).kerning(-0.5).foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            ReminderBell()
        }
        .padding(.top, 6)
    }
}

/// Toggles plan reminders. Reflects the real notification permission.
struct ReminderBell: View {
    @Environment(AppModel.self) private var model
    @State private var showDenied = false

    var body: some View {
        let on = model.remindersActive
        Button {
            if model.notificationsDenied { showDenied = true } else { Task { await model.setReminders(!model.state.remindersEnabled) } }
        } label: {
            Image(systemName: on ? "bell.fill" : "bell.slash")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(on ? Palette.ink : Palette.secondary)
                .frame(width: 38, height: 38)
                .background(Circle().fill(on ? Palette.surface : Color.clear))
                .overlay(Circle().strokeBorder(Palette.line))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Plan reminders")
        .accessibilityValue(model.notificationsDenied ? "Unavailable, notifications are off in Settings" : on ? "On" : "Off")
        .accessibilityHint(model.notificationsDenied ? "Explains how to allow notifications" : on ? "Turns reminders off" : "Turns reminders on")
        .alert("Notifications are off", isPresented: $showDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Rhythmic isn't allowed to send notifications. Turn them on in iOS Settings to get plan reminders.")
        }
    }
}

struct PlanView: View {
    let plan: Plan
    @State private var clock = Date()
    @State private var selectedDay = 0
    @State private var selectedBlock: PlanBlock?
    @State private var selectedEvent: FlightEvent?
    @State private var didScroll = false
    private let tick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var days: [TimelineDay] { TimelineLayout.days(for: plan) }

    var body: some View {
        let days = days
        let day = days[min(selectedDay, days.count - 1)]
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PlanHeader()
                    Text(plan.trip.title)
                        .font(.subheadline.weight(.medium)).foregroundStyle(Palette.secondary)
                        .padding(.top, 2)
                        .accessibilityLabel("Route: " + plan.trip.segments.map(\.origin).joined(separator: ", ") + ", " + plan.trip.last.destination)
                    DaySelector(days: days, selected: $selectedDay)
                        .padding(.top, 14)
                        .id("day-selector")
                    CurrentActionCard(plan: plan, now: clock)
                        .padding(.top, 14)
                    ForEach(plan.warnings.filter { $0.severity == .caution }, id: \.self) { w in
                        Label(w.message, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Palette.secondary)
                            .padding(.top, 10)
                    }
                    DayTimeline(plan: plan, day: day, now: clock,
                                onSelectBlock: { selectedBlock = $0 }, onSelectEvent: { selectedEvent = $0 })
                        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                        .padding(.top, 18)
                        .id(day.id)
                    dayFooter(days: days, day: day, proxy: proxy)
                        .padding(.top, 8).padding(.bottom, 24)
                }
                .padding(.horizontal, 16)
            }
            .background(Palette.background)
            .safeAreaInset(edge: .top, spacing: 0) {
                // Solid status-bar backing so content never scrolls under the clock.
                Color.clear.frame(height: 0).background(Palette.background.ignoresSafeArea(edges: .top))
            }
            .onAppear {
                selectedDay = defaultDay(days)
                scrollToNow(proxy, days: days)
            }
            .onChange(of: plan.id) { selectedDay = defaultDay(days) }
        }
        .onReceive(tick) { clock = $0 }
        .sheet(item: $selectedBlock) { BlockDetail(block: $0, plan: plan) }
        .sheet(item: $selectedEvent) { FlightEventDetail(event: $0, trip: plan.trip, plan: plan).presentationDetents([.medium, .large]) }
    }

    private func defaultDay(_ days: [TimelineDay]) -> Int {
        #if DEBUG
        // Debug builds only: `-RhythmicDay 2` opens that day page (for screenshots without taps).
        if let i = UserDefaults.standard.object(forKey: "RhythmicDay") as? Int ?? Int(UserDefaults.standard.string(forKey: "RhythmicDay") ?? ""), days.indices.contains(i) { return i }
        #endif
        return TimelineLayout.dayIndex(containing: Date(), in: days) ?? (Date() < plan.horizon.start ? 0 : days.count - 1)
    }

    private func scrollToNow(_ proxy: ScrollViewProxy, days: [TimelineDay]) {
        #if DEBUG
        // Debug builds only: `-RhythmicScrollHour 12` scrolls to that hour tick (screenshots without gestures).
        if let h = UserDefaults.standard.string(forKey: "RhythmicScrollHour") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { proxy.scrollTo("hour-\(h)", anchor: .top) }
            return
        }
        #endif
        guard !didScroll, TimelineLayout.dayIndex(containing: clock, in: days) != nil else { return }
        didScroll = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation { proxy.scrollTo("now", anchor: UnitPoint(x: 0.5, y: 0.35)) }
        }
    }

    @ViewBuilder
    private func dayFooter(days: [TimelineDay], day: TimelineDay, proxy: ScrollViewProxy) -> some View {
        if day.index + 1 < days.count {
            let next = days[day.index + 1]
            HStack {
                Spacer()
                Button {
                    selectedDay = next.index
                    // Start the next day from its top, not where the previous one ended.
                    DispatchQueue.main.async { withAnimation { proxy.scrollTo("day-selector", anchor: .top) } }
                } label: {
                    Label(TimeFmt.day(next.span.start, next.zoneIDAtStart), systemImage: "chevron.right")
                        .labelStyle(TrailingIconLabel())
                        .font(.footnote).foregroundStyle(Palette.secondary)
                }
                .accessibilityLabel("Next day, \(TimeFmt.day(next.span.start, next.zoneIDAtStart))")
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("End of plan").font(.footnote.weight(.medium)).foregroundStyle(Palette.ink)
                ForEach(plan.warnings.filter { $0.severity == .info }, id: \.self) { w in
                    Text(w.message).font(.caption).foregroundStyle(Palette.secondary)
                }
            }
        }
    }
}

private struct TrailingIconLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { configuration.title; configuration.icon.imageScale(.small) }
    }
}

struct DaySelector: View {
    let days: [TimelineDay]
    @Binding var selected: Int

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(days) { d in
                        let on = d.index == selected
                        Button { selected = d.index } label: {
                            VStack(spacing: 1) {
                                Text(TimeFmt.weekday(d.span.start, d.zoneIDAtStart).uppercased())
                                    .font(.system(size: 10, weight: .medium)).kerning(0.4)
                                Text("\(d.day)").font(.body.weight(.medium).monospacedDigit())
                            }
                            .foregroundStyle(on ? Palette.background : Palette.secondary)
                            .frame(minWidth: 44, minHeight: 48)
                            .padding(.horizontal, 2)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(on ? Palette.ink : Color.clear))
                        }
                        .buttonStyle(.plain)
                        .id(d.index)
                        .accessibilityLabel(TimeFmt.day(d.span.start, d.zoneIDAtStart))
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .frame(minWidth: 0)
            }
            .onChange(of: selected) { _, i in withAnimation { proxy.scrollTo(i, anchor: .center) } }
            .onAppear { proxy.scrollTo(selected, anchor: .center) }
        }
    }
}

/// What the plan says to do right now, and what comes next. Uses the real current time and
/// shows plan times only (never the current clock time or location).
struct CurrentActionCard: View {
    let plan: Plan
    let now: Date

    struct Step { var title: String; var icon: String; var date: Date }

    var body: some View {
        let content = self.content
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: content.icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Palette.cardIcon)
                .frame(width: 26, height: 26)
                .padding(.top, 14)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("NOW").font(.system(size: 10, weight: .semibold)).kerning(1).foregroundStyle(Palette.secondary)
                Text(content.title).font(.headline.weight(.medium)).foregroundStyle(Palette.ink)
                if let sub = content.subtitle {
                    Text(sub).font(.caption).foregroundStyle(Palette.secondary)
                }
                if let next = content.next {
                    Divider().overlay(Palette.line).padding(.vertical, 6)
                    HStack(spacing: 4) {
                        Text("Up next").foregroundStyle(Palette.secondary)
                        Text("\(TimeFmt.clock(next.date, trip: plan.trip, relativeTo: now)) · \(next.title)")
                            .fontWeight(.medium).foregroundStyle(Palette.ink)
                    }
                    .font(.caption)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 17, style: .continuous).fill(Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).strokeBorder(Palette.line))
        .accessibilityElement(children: .combine)
    }

    private struct Content { var icon: String; var title: String; var subtitle: String?; var next: Step? }

    private var content: Content {
        let all = TimelineLayout.mainLane(plan, in: plan.horizon)
        if now < plan.horizon.start {
            return Content(icon: "calendar", title: "Plan starts \(TimeFmt.day(plan.horizon.start, plan.trip.clockZoneID(at: plan.horizon.start)))",
                           subtitle: nil, next: nextStep(after: plan.horizon.start.addingTimeInterval(-1), current: nil, items: all))
        }
        if now >= plan.horizon.end {
            return Content(icon: "checkmark.circle", title: "Plan complete",
                           subtitle: "Keep regular local sleep times and get morning daylight.", next: nil)
        }
        let current = all.first { $0.span.contains(now) }
        let flight = plan.trip.segment(airborneAt: now)
        guard let current else {
            if let flight {
                return Content(icon: "airplane", title: "In flight", subtitle: "\(flight.origin) → \(flight.destination)",
                               next: nextStep(after: now, current: nil, items: all))
            }
            return Content(icon: "clock", title: "Nothing scheduled", subtitle: "Follow local time",
                           next: nextStep(after: now, current: nil, items: all))
        }
        let end = runEnd(of: current, in: all)
        var sub = "Until \(TimeFmt.clock(end, trip: plan.trip, relativeTo: now))"
        if let s = current.block.displaySubtitle { sub += " · \(s)" }
        return Content(icon: current.block.kind.icon, title: current.block.displayTitle, subtitle: sub,
                       next: nextStep(after: now, current: current, items: all))
    }

    /// End of a run of contiguous blocks with the same title (e.g. light split at sunrise).
    private func runEnd(of item: LaneItem, in items: [LaneItem]) -> Date {
        var end = item.span.end
        while let n = items.first(where: { $0.span.start == end && $0.block.displayTitle == item.block.displayTitle }) { end = n.span.end }
        return end
    }

    private func nextStep(after t: Date, current: LaneItem?, items: [LaneItem]) -> Step? {
        var candidates: [Step] = []
        let currentEnd = current.map { runEnd(of: $0, in: items) }
        if let n = items.first(where: { $0.span.start > t && $0.span.start >= (currentEnd ?? t) }) {
            candidates.append(Step(title: n.block.displayTitle, icon: n.block.kind.icon, date: n.span.start))
        }
        if let cutoff = plan.blocks.first(where: { $0.kind == .caffeineAvoid && $0.start > t }) {
            candidates.append(Step(title: "Coffee cutoff", icon: "cup.and.saucer", date: cutoff.start))
        }
        for s in plan.trip.segments {
            if s.departure > t { candidates.append(Step(title: "Depart \(s.origin)", icon: "airplane.departure", date: s.departure)) }
            if s.arrival > t { candidates.append(Step(title: "Land \(s.destination)", icon: "airplane.arrival", date: s.arrival)) }
        }
        return candidates.filter { $0.date < plan.horizon.end }.min { $0.date < $1.date }
    }
}

// MARK: - Details

struct BlockDetail: View {
    let block: PlanBlock
    let plan: Plan
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label { Text(block.displayTitle).font(.headline) } icon: { KindIcon(kind: block.kind) }
                    Text(block.detail)
                    if let r = block.recommendedMinutes {
                        Text("This is a \(TimeFmt.duration(block.span.duration)) window. Suggested: \(r.lowerBound)–\(r.upperBound) min, any time within it.")
                            .font(.callout)
                    }
                }
                Section("Time") {
                    let sz = plan.trip.clockZoneID(at: block.start), ez = plan.trip.clockZoneID(at: block.end)
                    row("Local", "\(TimeFmt.dayTime(block.start, sz)) – \(TimeFmt.dayTime(block.end, ez))"
                        + (sz == ez ? " (\(plan.trip.clockCity(at: block.start)))" : " (\(plan.trip.clockCity(at: block.start)) → \(plan.trip.clockCity(at: block.end)))"))
                    row("Length", TimeFmt.duration(block.span.duration))
                    if plan.preferences.showHomeTime && (sz != plan.homeZoneID || ez != plan.homeZoneID) {
                        row("Home", "\(TimeFmt.dayTime(block.start, plan.homeZoneID)) – \(TimeFmt.dayTime(block.end, plan.homeZoneID)) (\(TimeFmt.city(plan.homeZoneID)))")
                    }
                }
                if !block.ruleIDs.isEmpty {
                    Section("Why?") {
                        ForEach(block.ruleIDs.compactMap(RuleBook.rule), id: \.id) { rule in
                            DisclosureGroup {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(rule.basis.rawValue).font(.caption.weight(.semibold))
                                        .foregroundStyle(rule.basis == .sourceSupported ? Color.green : Color.orange)
                                    Text("Evidence: \(rule.evidenceType)").font(.caption)
                                    Text("Assumptions: \(rule.assumptions)").font(.caption)
                                    ForEach(rule.sources, id: \.self) { Text($0).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled) }
                                    Text("Reviewed \(rule.reviewed)").font(.caption2).foregroundStyle(.secondary)
                                }
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(rule.title).font(.subheadline.weight(.semibold))
                                    Text(rule.plainExplanation).font(.footnote)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(block.kind.legendLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
        }
    }

    func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) { Text(k).foregroundStyle(.secondary).frame(width: 60, alignment: .leading); Text(v).font(.callout.monospacedDigit()) }
    }
}

/// Takeoff or landing details from the actual itinerary.
struct FlightEventDetail: View {
    let event: FlightEvent
    let trip: Trip
    let plan: Plan
    @Environment(\.dismiss) private var dismiss

    var s: FlightSegment { event.segment }
    func city(_ code: String) -> String { Airports.lookup(code)?.city ?? code }
    func local(_ d: Date, _ zone: String, _ code: String) -> String {
        "\(TimeFmt.dayTime(d, zone)) \(TimeFmt.zoneAbbrev(zone, at: d)) · \(city(code))"
    }

    var body: some View {
        let i = trip.segments.firstIndex(of: s) ?? 0
        NavigationStack {
            List {
                Section {
                    row("Flight", s.displayFlight)
                    row("Route", "\(city(s.origin)) (\(s.origin)) → \(city(s.destination)) (\(s.destination))")
                    row(event.kind == .takeoff ? "Departs" : "Arrives", local(event.date, event.zoneID, event.airport))
                    if event.kind == .takeoff { row("Arrives", local(s.arrival, s.destinationZoneID, s.destination)) }
                    else { row("Departed", local(s.departure, s.originZoneID, s.origin)) }
                    row("Flight time", TimeFmt.duration(s.span.duration))
                }
                if event.kind == .landing, i + 1 < trip.segments.count {
                    let n = trip.segments[i + 1]
                    Section("Connection") {
                        row("Time on ground", TimeFmt.duration(n.departure.timeIntervalSince(s.arrival)))
                        row("Next flight", "\(n.displayFlight) · \(n.origin) → \(n.destination)")
                        row("Departs", local(n.departure, n.originZoneID, n.origin))
                        if n.origin != s.destination { Text("Different departure airport: allow time for the transfer.").font(.footnote).foregroundStyle(.orange) }
                    }
                } else if event.kind == .takeoff, i > 0 {
                    let p = trip.segments[i - 1]
                    Section("Connection") {
                        row("After", "\(TimeFmt.duration(s.departure.timeIntervalSince(p.arrival))) on the ground in \(city(p.destination))")
                    }
                }
                if plan.preferences.showHomeTime, event.zoneID != plan.homeZoneID {
                    Section("Home time") { row("Home", "\(TimeFmt.dayTime(event.date, plan.homeZoneID)) (\(TimeFmt.city(plan.homeZoneID)))") }
                }
                Section {
                    Text(event.kind == .landing
                         ? "The plan's clock switches to \(city(event.airport)) time when you land."
                         : "Times are scheduled, from your itinerary. Rhythmic doesn't track live delays.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(event.kind == .takeoff ? "Depart \(city(event.airport))" : "Arrive \(city(event.airport))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
        }
    }

    func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k).foregroundStyle(.secondary).frame(width: 96, alignment: .leading)
            Text(v).font(.callout.monospacedDigit())
        }
    }
}

struct AboutPlan: View {
    var plan: Plan?

    var body: some View {
        List {
            Section {
                Text("Rhythmic estimates your body clock from your usual sleep times. That's a rough starting point, not a measurement. It then times light, darkness, sleep and caffeine to help your clock move toward local time.")
                Text("Three things get mixed up: body-clock timing, how much sleep you've had, and short-term alertness (from caffeine or light). They're related, but feeling alert doesn't mean your clock has adjusted.")
                Text("The plan doesn't change if you miss sleep, and it doesn't know whether you followed it. If you're exhausted, rest. It shows two days after arrival; adjusting fully usually takes longer.")
            }
            if let plan {
                Section("Current plan") {
                    Text(summary(plan))
                    ForEach(plan.warnings, id: \.self) { Text($0.message).font(.footnote) }
                }
            }
            Section("Reading the timeline") {
                ForEach([BlockKind.prioritizeLight, .lightHelpful, .nap, .reduceLight, .sleep, .caffeineOK, .caffeineAvoid], id: \.self) { k in
                    Label { Text(k.legendLabel).font(.footnote) } icon: { KindIcon(kind: k) }
                }
                Text("Blocks are drawn to scale. A window, such as a 3-hour nap window, means a short nap any time within it, not 3 hours of sleep. Coffee OK means permitted, not a cue to keep drinking. Tap any block for exact times and why.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("The clock on the left shows the local time where you most recently landed. It switches at each landing, marked with the place name.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("All rules (\(RuleBook.version))") {
                ForEach(RuleBook.all, id: \.id) { r in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(r.id) · \(r.title)").font(.subheadline.weight(.semibold))
                        Text(r.plainExplanation).font(.footnote)
                        Text(r.basis.rawValue).font(.caption2).foregroundStyle(r.basis == .sourceSupported ? Color.green : Color.orange)
                    }
                }
            }
            Section("Not included in this version") {
                Text("Melatonin, adjusting after missed sleep, sleep tracking or wearables, live airline delays, and short trips where staying on home time is better.")
                    .font(.footnote)
            }
        }
        .navigationTitle("How this plan works")
        .navigationBarTitleDisplayMode(.inline)
    }

    func summary(_ plan: Plan) -> String {
        let s = plan.strategy
        let h = TimeFmt.duration(abs(s.zoneDifferenceHours) * 3600)
        switch s.direction {
        case .advance: return "Destination is \(h) ahead. The plan moves your sleep and light earlier."
        case .delay: return s.zoneDifferenceHours > 0
            ? "Destination is \(h) ahead. For a change this large, the plan moves your clock later instead."
            : "Destination is \(h) behind. The plan moves your sleep and light later."
        case .none: return "Small time change. The plan follows local time."
        }
    }
}
