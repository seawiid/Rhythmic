import SwiftUI
import RhythmicCore

struct PlanView: View {
    @Environment(AppModel.self) private var model
    let plan: Plan
    @State private var selected: PlanBlock?
    @State private var showAbout = false
    @State private var previewOffset: Double = 0
    @State private var clock = Date()
    private let tick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    /// Real time, unless the user is previewing a moment (useful before the plan starts).
    var isPreviewing: Bool { !plan.horizon.contains(clock) }
    var now: Date {
        isPreviewing ? plan.horizon.start.addingTimeInterval(previewOffset * plan.horizon.duration) : clock
    }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                NowCard(plan: plan, now: now)
                if isPreviewing { previewControl }
                if !plan.warnings.isEmpty { warnings }
                RemindersCard()
                DisclosureGroup("Key") { Legend().padding(.top, 6) }
                    .padding(.horizontal)
                PlanTimeline(plan: plan, now: now) { selected = $0 }
                footer
            }
            .padding(.vertical)
        }
        .onAppear {
            #if DEBUG
            // Debug/demo only: `-RhythmicPreview 2026-11-23T14:00:00Z` opens the plan at that moment.
            if let s = UserDefaults.standard.string(forKey: "RhythmicPreview"), let d = ISO8601DateFormatter().date(from: s), plan.horizon.contains(d) {
                previewOffset = d.timeIntervalSince(plan.horizon.start) / plan.horizon.duration
            }
            #endif
            // Open on the current (or previewed) day, unless that's the plan's first day.
            let key = TimeFmt.day(now, plan.trip.zoneID(at: now))
            if key != TimeFmt.day(plan.horizon.start, plan.homeZoneID) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { proxy.scrollTo("day-" + key, anchor: .top) }
            }
        }
        }
        .onReceive(tick) { clock = $0 }
        .sheet(item: $selected) { BlockDetail(block: $0, plan: plan) }
        .sheet(isPresented: $showAbout) { AboutPlan(plan: plan) }
    }

    var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            if plan.trip.segments.contains(where: { $0.sources.contains { $0.kind == .sample } }) {
                Label("Sample itinerary: not your real flights", systemImage: "testtube.2")
                    .font(.caption.weight(.semibold)).foregroundStyle(.orange)
            }
            Text(plan.trip.title).font(.title2.bold())
            Text(summary).font(.subheadline).foregroundStyle(.secondary)
            Button("How this plan works") { showAbout = true }.font(.footnote)
        }
        .padding(.horizontal)
    }

    var summary: String {
        let s = plan.strategy
        let h = TimeFmt.duration(abs(s.zoneDifferenceHours) * 3600)
        switch s.direction {
        case .advance: return "Destination is \(h) ahead. Plan moves your sleep and light earlier."
        case .delay: return s.zoneDifferenceHours > 0
            ? "Destination is \(h) ahead. For a change this large, the plan moves your clock later instead."
            : "Destination is \(h) behind. Plan moves your sleep and light later."
        case .none: return "Small time change. Plan follows local time."
        }
    }

    var previewControl: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(clock < plan.horizon.start ? "Plan starts \(TimeFmt.dayTime(plan.horizon.start, plan.homeZoneID)). Preview a moment:" : "Plan has ended. Preview a moment:")
                .font(.caption).foregroundStyle(.secondary)
            Slider(value: $previewOffset, in: 0...0.999, step: 1.0 / Double(Int(plan.horizon.duration / 900)))
                .accessibilityLabel("Preview time")
                .accessibilityValue(TimeFmt.dayTime(now, plan.trip.zoneID(at: now)))
        }
        .padding(.horizontal)
    }

    var warnings: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(plan.warnings, id: \.self) { w in
                Label(w.message, systemImage: w.severity == .caution ? "exclamationmark.triangle" : "info.circle")
                    .font(.footnote)
                    .foregroundStyle(w.severity == .caution ? Color.orange : Color.secondary)
            }
        }
        .padding(.horizontal)
    }

    var footer: some View {
        Text("General, research-informed suggestions. Not a measurement of your body clock, not medical advice, no guaranteed results. Rest when you need to. Rules \(plan.ruleVersion).")
            .font(.caption2).foregroundStyle(.secondary).padding(.horizontal)
    }
}

/// The current action(s): one clear recommendation, no check-in.
struct NowCard: View {
    let plan: Plan
    let now: Date

    var active: [PlanBlock] {
        let order: [BlockKind] = [.sleep, .reduceLight, .prioritizeLight, .nap, .lightHelpful, .caffeineAvoid, .caffeineOK]
        return plan.blocks(at: now).filter { $0.kind != .flight }.sorted { order.firstIndex(of: $0.kind)! < order.firstIndex(of: $1.kind)! }
    }

    var next: PlanTransition? { NotificationPlanner().transitions(for: plan).first { $0.date > now } }

    var body: some View {
        let zone = plan.trip.zoneID(at: now)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Now").font(.headline)
                Spacer()
                Text("\(TimeFmt.dayTime(now, zone)) \(TimeFmt.city(zone))").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            if let flight = plan.trip.segment(airborneAt: now) {
                Label("On \(flight.origin) → \(flight.destination)", systemImage: "airplane").font(.footnote).foregroundStyle(.secondary)
            }
            if let primary = active.first {
                HStack(alignment: .top, spacing: 10) {
                    KindIcon(kind: primary.kind).font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(primary.title).font(.title3.bold())
                        Text(primary.detail).font(.subheadline)
                        Text("Until \(TimeFmt.time(primary.end, plan.trip.zoneID(at: primary.end)))").font(.caption).foregroundStyle(.secondary)
                    }
                }
                let others = active.dropFirst().filter { $0.kind.lane != primary.kind.lane }
                if !others.isEmpty {
                    HStack(spacing: 12) {
                        ForEach(others) { b in Label(b.title, systemImage: b.kind.icon).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            } else {
                Text("Nothing specific right now.").font(.subheadline).foregroundStyle(.secondary)
            }
            if let next {
                Divider()
                Text("Next: \(next.title) at \(TimeFmt.time(next.date, plan.trip.zoneID(at: next.date)))").font(.footnote)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
    }
}

struct RemindersCard: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Reminders", isOn: Binding(get: { model.state.remindersEnabled }, set: { on in Task { await model.setReminders(on) } }))
                .font(.headline)
            Text(model.state.remindersEnabled
                 ? "\(model.pendingReminderCount) reminders scheduled on this iPhone. They work offline and stop when the plan ends. They're ordinary notifications, not alarms: Silent mode or Focus can hide them, so set a real alarm if you need to wake."
                 : "Get short reminders at key moments, like daylight, lights low, coffee cutoff, bedtime and wake time.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }
}

struct BlockDetail: View {
    let block: PlanBlock
    let plan: Plan
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label { Text(block.title).font(.headline) } icon: { KindIcon(kind: block.kind) }
                    Text(block.detail)
                    if let r = block.recommendedMinutes {
                        Text("This is a \(TimeFmt.duration(block.span.duration)) window. Suggested: \(r.lowerBound)–\(r.upperBound) min, any time within it.")
                            .font(.callout)
                    }
                }
                Section("Time") {
                    row("Local", "\(TimeFmt.dayTime(block.start, block.zoneID)) – \(TimeFmt.dayTime(block.end, plan.trip.zoneID(at: block.end))) (\(TimeFmt.city(block.zoneID)))")
                    if plan.preferences.showHomeTime && block.zoneID != plan.homeZoneID {
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
        HStack(alignment: .top) { Text(k).foregroundStyle(.secondary).frame(width: 50, alignment: .leading); Text(v).font(.callout.monospacedDigit()) }
    }
}

struct AboutPlan: View {
    let plan: Plan
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Rhythmic estimates your body clock from your usual sleep times. That's a rough starting point, not a measurement. It then times light, darkness, sleep and caffeine to help your clock move toward local time.")
                    Text("Three things get mixed up: body-clock timing, how much sleep you've had, and short-term alertness (from caffeine or light). They're related, but feeling alert doesn't mean your clock has adjusted.")
                    Text("The plan doesn't change if you miss sleep, and it doesn't know whether you followed it. If you're exhausted, rest. It shows two days after arrival; adjusting fully usually takes longer.")
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
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}
