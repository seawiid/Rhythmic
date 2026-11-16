import SwiftUI
import RhythmicCore

/// Vertically scrolling timeline. Each local day is a section: hour ruler on the left, three lanes
/// (sleep · light · caffeine), and labels on the right placed at block start without overlapping.
/// Solid fills = do this for the whole period. Translucent/outlined = a window; its label states
/// the suggested duration within it.
struct PlanTimeline: View {
    let plan: Plan
    var now: Date
    var onSelect: (PlanBlock) -> Void

    static let hourHeight: CGFloat = 30
    static let laneWidth: CGFloat = 14

    struct Day: Identifiable {
        var id: String
        var zone: String
        var span: TimeSpan
        var phase: PlanPhase
    }

    /// Split the horizon into local days, following the traveller's zone.
    var days: [Day] {
        var out: [Day] = []
        var t = plan.horizon.start
        while t < plan.horizon.end {
            let zone = plan.trip.zoneID(at: t)
            let key = TimeFmt.day(t, zone)
            if var last = out.last, last.id == key {
                last.span = TimeSpan(last.span.start, t.addingTimeInterval(3600))
                out[out.count - 1] = last
            } else {
                out.append(Day(id: key, zone: zone, span: TimeSpan(t, t.addingTimeInterval(3600)), phase: plan.phase(at: t)))
            }
            // A day containing any part of the journey is a travel day.
            if var last = out.last, last.span.overlaps(TimeSpan(plan.trip.departure.addingTimeInterval(-3 * 3600), plan.trip.arrival)) {
                last.phase = .travel; out[out.count - 1] = last
            }
            t = t.addingTimeInterval(3600)
        }
        return out
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
            ForEach(days) { day in
                Section {
                    DayCanvas(plan: plan, day: day, now: now, onSelect: onSelect)
                        .id("day-" + day.id)
                } header: {
                    DayHeader(plan: plan, day: day)
                }
            }
        }
    }
}

private struct DayHeader: View {
    let plan: Plan
    let day: PlanTimeline.Day
    var body: some View {
        HStack {
            Text(day.id).font(.headline)
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(TimeFmt.city(day.zone)).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 6).padding(.horizontal)
        .background(.bar)
        .accessibilityElement(children: .combine)
    }
    var label: String {
        switch day.phase { case .preparation: "Preparation"; case .travel: "Travel"; case .destination: "Destination" }
    }
}

private struct DayCanvas: View {
    let plan: Plan
    let day: PlanTimeline.Day
    let now: Date
    var onSelect: (PlanBlock) -> Void

    let rulerWidth: CGFloat = 64
    let labelHeight: CGFloat = 40

    var hours: Int { Int((day.span.duration / 3600).rounded()) }
    func y(_ d: Date) -> CGFloat { CGFloat(d.timeIntervalSince(day.span.start) / 3600) * PlanTimeline.hourHeight }

    var visibleBlocks: [PlanBlock] { plan.blocks.filter { $0.span.overlaps(day.span) } }

    /// Labels for blocks that start in this day (or continue from the previous day at the top).
    var labelled: [(PlanBlock, CGFloat)] {
        var out: [(PlanBlock, CGFloat)] = []
        var cursor: CGFloat = 0
        for b in visibleBlocks {
            let y0 = max(0, y(b.start))
            let placed = max(y0, cursor)
            out.append((b, placed))
            cursor = placed + labelHeight
        }
        return out
    }

    var body: some View {
        let height = max(CGFloat(hours) * PlanTimeline.hourHeight, (labelled.last?.1 ?? 0) + labelHeight)
        ZStack(alignment: .topLeading) {
            // Hour ruler
            ForEach(0..<hours, id: \.self) { h in
                let t = day.span.start.addingTimeInterval(Double(h) * 3600)
                // Ruler follows the traveller's zone hour by hour, so it always matches the labels.
                let zone = plan.trip.zoneID(at: t)
                let zoneChanged = h > 0 && zone != plan.trip.zoneID(at: t.addingTimeInterval(-3600))
                HStack(alignment: .top, spacing: 4) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(TimeFmt.time(t, zone)).font(.caption2.monospacedDigit().weight(zoneChanged ? .bold : .regular))
                        if zoneChanged {
                            Text(TimeFmt.city(zone)).font(.caption2).foregroundStyle(.tint).lineLimit(1).minimumScaleFactor(0.7)
                        } else if plan.preferences.showHomeTime, h % 2 == 0,
                           let home = TimeFmt.homeReference(t, local: zone, home: plan.homeZoneID) {
                            Text(home).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
                        }
                    }
                    .frame(width: rulerWidth, alignment: .trailing)
                    Rectangle().fill(.quaternary).frame(height: 0.5)
                }
                .offset(y: CGFloat(h) * PlanTimeline.hourHeight - 6)
                .accessibilityHidden(true)
            }

            // Lanes
            ForEach(visibleBlocks) { b in
                lane(for: b)
            }

            // Now marker
            if day.span.contains(now) {
                Rectangle().fill(.red).frame(height: 2)
                    .offset(x: rulerWidth, y: y(now))
                    .accessibilityLabel("Now")
            }

            // Labels
            ForEach(labelled, id: \.0.id) { b, ly in
                Button { onSelect(b) } label: { BlockLabel(block: b, plan: plan) }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, minHeight: labelHeight, maxHeight: labelHeight, alignment: .topLeading)
                    .padding(.leading, rulerWidth + 3 * (PlanTimeline.laneWidth + 4) + 14)
                    .padding(.trailing, 12)
                    .offset(y: ly)
            }
        }
        .frame(height: height + 8, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    @ViewBuilder
    func lane(for b: PlanBlock) -> some View {
        let laneIndex: CGFloat = switch b.kind.lane { case .sleep: 0; case .light: 1; case .caffeine: 2; case .context: 0 }
        let top = max(0, y(b.start)), bottom = min(CGFloat(hours) * PlanTimeline.hourHeight, y(b.end))
        let x = rulerWidth + 6 + laneIndex * (PlanTimeline.laneWidth + 4)
        let h = max(2, bottom - top)
        Group {
            switch b.kind {
            case .flight:
                // Flight: thin bracket spanning all lanes.
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(Color.secondary, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    .frame(width: 3 * (PlanTimeline.laneWidth + 4) + 4, height: h)
                    .offset(x: x - 3, y: top)
            case .sleep, .prioritizeLight:
                RoundedRectangle(cornerRadius: 4).fill(b.kind.color)
                    .frame(width: PlanTimeline.laneWidth, height: h).offset(x: x, y: top)
            case .nap, .lightHelpful:
                RoundedRectangle(cornerRadius: 4).fill(b.kind.color.opacity(0.3))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(b.kind.color, style: StrokeStyle(lineWidth: 1.5, dash: b.kind == .nap ? [3, 2] : [])))
                    .frame(width: PlanTimeline.laneWidth, height: h).offset(x: x, y: top)
            case .reduceLight:
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(b.kind.color, lineWidth: 1.5)
                    .frame(width: PlanTimeline.laneWidth, height: h).offset(x: x, y: top)
            case .caffeineOK:
                // Dotted line: permitted window, not continuous drinking.
                Rectangle().fill(.clear).frame(width: PlanTimeline.laneWidth, height: h)
                    .overlay(Line().stroke(b.kind.color, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [1, 6])))
                    .offset(x: x, y: top)
            case .caffeineAvoid:
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(b.kind.color.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .overlay(CrossHatch().stroke(b.kind.color.opacity(0.35), lineWidth: 1).clipped())
                    .frame(width: PlanTimeline.laneWidth, height: h).offset(x: x, y: top)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct Line: Shape {
    func path(in r: CGRect) -> Path { Path { p in p.move(to: CGPoint(x: r.midX, y: r.minY + 2)); p.addLine(to: CGPoint(x: r.midX, y: r.maxY - 2)) } }
}

private struct CrossHatch: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            var y: CGFloat = -r.width
            while y < r.height {
                p.move(to: CGPoint(x: 0, y: y + r.width)); p.addLine(to: CGPoint(x: r.width, y: y))
                y += 8
            }
        }
    }
}

struct BlockLabel: View {
    let block: PlanBlock
    let plan: Plan

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            KindIcon(kind: block.kind).font(.footnote).frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(block.title).font(.footnote.weight(.semibold))
                    if let r = block.recommendedMinutes {
                        Text("· \(r.lowerBound)–\(r.upperBound) min in window").font(.caption2).foregroundStyle(.secondary)
                    }
                    if block.isOptional && block.recommendedMinutes == nil {
                        Text("· optional").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text(timeRange).font(.caption2.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility)
        .accessibilityHint("Shows details and why")
    }

    var timeRange: String {
        if block.kind == .flight, let s = plan.trip.segments.first(where: { $0.id == block.segmentID }) {
            return "Departs \(TimeFmt.time(s.departure, s.originZoneID)) \(TimeFmt.zoneAbbrev(s.originZoneID, at: s.departure)) · arrives \(TimeFmt.dayTime(s.arrival, s.destinationZoneID)) \(TimeFmt.zoneAbbrev(s.destinationZoneID, at: s.arrival))"
        }
        let endZone = plan.trip.zoneID(at: block.end)
        let start = TimeFmt.time(block.start, block.zoneID)
        let end = TimeFmt.day(block.start, block.zoneID) == TimeFmt.day(block.end, endZone)
            ? TimeFmt.time(block.end, endZone) : TimeFmt.dayTime(block.end, endZone)
        return "\(start)–\(end)" + (block.kind.isWindow || block.kind == .prioritizeLight ? " (window \(TimeFmt.duration(block.span.duration)))" : "")
    }

    var accessibility: String {
        var s = "\(block.kind.legendLabel). \(block.title). \(timeRange)."
        if let r = block.recommendedMinutes { s += " Suggested \(r.lowerBound) to \(r.upperBound) minutes, any time in the window." }
        if block.isOptional { s += " Optional." }
        return s
    }
}

struct Legend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach([BlockKind.sleep, .nap, .prioritizeLight, .lightHelpful, .reduceLight, .caffeineOK, .caffeineAvoid], id: \.self) { k in
                Label { Text(k.legendLabel).font(.footnote) } icon: { KindIcon(kind: k) }
            }
            Text("Solid bars: do this for the whole period. Outlined or faint bars: a window when it helps. The label says how long, e.g. a 3-hour nap window means a 20–30 min nap, not 3 hours of sleep. Dotted caffeine line: permitted, not a cue to keep drinking.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
