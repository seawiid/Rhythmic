import SwiftUI
import UIKit
import RhythmicCore

/// One local day of the plan as a time-proportional vertical timeline:
/// time column · flight-marker gutter · recommendation lane · caffeine lane.
/// Geometry follows elapsed time; the clock labels follow the most recently reached place
/// (see `Trip.clockZoneID(at:)`), so a landing relabels the clock without moving any block.
struct DayTimeline: View {
    let plan: Plan
    let day: TimelineDay
    let now: Date
    var onSelectBlock: (PlanBlock) -> Void
    var onSelectEvent: (FlightEvent) -> Void

    @ScaledMetric(relativeTo: .caption2) private var pointsPerHour: CGFloat = 40
    @ScaledMetric(relativeTo: .caption2) private var timeHeight: CGFloat = 15
    @ScaledMetric(relativeTo: .caption2) private var cityLine: CGFloat = 12
    @ScaledMetric(relativeTo: .caption2) private var timeWidthScaled: CGFloat = 48
    @ScaledMetric(relativeTo: .caption2) private var caffeineWidthScaled: CGFloat = 62
    /// Side columns grow with text size only up to a cap, so the main lane keeps room for titles.
    private var timeWidth: CGFloat { min(timeWidthScaled, 64) }
    private var caffeineWidth: CGFloat { min(caffeineWidthScaled, 72) }
    private let gutterWidth: CGFloat = 22
    private let laneGap: CGFloat = 6

    private var height: CGFloat { y(day.span.end) }
    private func y(_ d: Date) -> CGFloat { CGFloat(d.timeIntervalSince(day.span.start) / 3600) * pointsPerHour }
    /// City names may wrap to two lines in the narrow time column.
    private var metrics: LabelMetrics {
        let line = cityLine, width = timeWidth - 4
        let font = UIFontMetrics(forTextStyle: .caption2).scaledFont(for: .systemFont(ofSize: 10, weight: .medium))
        return LabelMetrics(timeHeight: timeHeight, gap: 2) { city in
            (city as NSString).size(withAttributes: [.font: font]).width * 0.75 > width ? line * 2 : line
        }
    }

    var body: some View {
        let labels = TimelineLayout.labels(plan, day: day, pointsPerHour: pointsPerHour, metrics: metrics)
        let overflow = max(0, (labels.map(\.bottom).max() ?? 0) - height)
        HStack(alignment: .top, spacing: 0) {
            timeColumn(labels).frame(width: timeWidth, height: height, alignment: .topTrailing)
            gutter.frame(width: gutterWidth, height: height)
            Color.clear.frame(width: laneGap, height: height)
            lanes.frame(height: height)
        }
        .padding(.top, timeHeight / 2 + 2)
        .padding(.bottom, overflow + timeHeight / 2 + 4)
    }

    // MARK: Time column

    private func timeColumn(_ labels: [TimelineLabel]) -> some View {
        ZStack(alignment: .topTrailing) {
            ForEach(labels, id: \.self) { l in
                VStack(alignment: .trailing, spacing: 0) {
                    Text(TimeFmt.time(l.date, l.zoneID))
                        .font(.caption2.monospacedDigit().weight(isEvent(l) ? .semibold : .regular))
                        .foregroundStyle(isEvent(l) ? Palette.ink : Palette.secondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .frame(height: timeHeight)
                    if let city = l.city {
                        Text(city)
                            .font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.accent)
                            .multilineTextAlignment(.trailing).lineLimit(2).minimumScaleFactor(0.75)
                            .frame(height: metrics.cityHeight(city), alignment: .top)
                    }
                }
                .frame(width: timeWidth - 4, alignment: .trailing)
                .offset(y: l.top)
            }
        }
        .accessibilityHidden(true)
    }

    private func isEvent(_ l: TimelineLabel) -> Bool { if case .event = l.kind { true } else { false } }

    // MARK: Flight gutter

    private var gutter: some View {
        let events = TimelineLayout.flightEvents(plan.trip, in: day.span)
        let airborne = plan.trip.segments.compactMap { $0.span.intersection(day.span) }
        return ZStack(alignment: .top) {
            ForEach(airborne, id: \.start) { s in
                // Thin dotted trail while airborne: sits in the gutter, never across the blocks.
                Rectangle().fill(.clear).frame(width: 2, height: max(0, y(s.end) - y(s.start)))
                    .overlay(DottedLine().stroke(Palette.accent.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [0.5, 4])))
                    .offset(y: y(s.start))
            }
            ForEach(events) { e in
                Button { onSelectEvent(e) } label: {
                    Image(systemName: e.kind == .takeoff ? "airplane.departure" : "airplane.arrival")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Palette.background))
                        .contentShape(Rectangle().inset(by: -4))
                }
                .buttonStyle(.plain)
                .offset(y: y(e.date) - 10)
                .accessibilityLabel(eventLabel(e))
                .accessibilityHint("Shows flight details")
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func eventLabel(_ e: FlightEvent) -> String {
        let place = Airports.lookup(e.airport)?.city ?? e.airport
        return "\(e.kind == .takeoff ? "Takeoff from" : "Landing in") \(place), \(TimeFmt.time(e.date, e.zoneID)) local time"
    }

    // MARK: Lanes

    private var lanes: some View {
        let main = TimelineLayout.mainLane(plan, in: day.span)
        let caffeine = TimelineLayout.caffeineLane(plan, in: day.span)
        let ticks = TimelineLayout.hourTicks(plan.trip, in: day.span).map(y)
        return HStack(alignment: .top, spacing: laneGap) {
            ZStack(alignment: .top) {
                ForEach(main) { item in
                    BlockCell(item: item, past: item.span.end <= now, caffeine: false) { onSelectBlock(item.block) }
                        .frame(height: max(1, y(item.span.end) - y(item.span.start) - 2))
                        .offset(y: y(item.span.start) + 1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            ZStack(alignment: .top) {
                ForEach(caffeine) { item in
                    BlockCell(item: item, past: item.span.end <= now, caffeine: true) { onSelectBlock(item.block) }
                        .frame(height: max(1, y(item.span.end) - y(item.span.start) - 2))
                        .offset(y: y(item.span.start) + 1)
                }
            }
            .frame(width: caffeineWidth)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .background(alignment: .top) {
            Canvas { ctx, size in
                for t in ticks {
                    ctx.fill(Path(CGRect(x: 0, y: t - 0.25, width: size.width, height: 0.5)), with: .color(Palette.line))
                }
            }
            .accessibilityHidden(true)
        }
        .overlay(alignment: .topLeading) { nowLine }
        .background(alignment: .topLeading) {
            // Scroll anchors at each hour tick (used to open on "now" and by debug screenshots).
            ZStack(alignment: .topLeading) {
                ForEach(Array(ticks.enumerated()), id: \.offset) { i, t in
                    Color.clear.frame(width: 1, height: 1).padding(.top, t).id("hour-\(i)")
                }
            }
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var nowLine: some View {
        if day.span.contains(now) {
            let ny = y(now)
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Palette.now.opacity(0.5)).frame(height: 1.5).offset(y: ny - 0.75)
                Circle().fill(Palette.now.opacity(0.85)).frame(width: 7, height: 7).offset(x: -3.5, y: ny - 3.5)
                // Scroll anchor (padding, not offset, so ScrollViewReader sees the position).
                Color.clear.frame(width: 1, height: 1).padding(.top, ny).id("now")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// A solid, rounded block. Content adapts to the space the duration gives it: title and one
/// short line, title only, icon only, or nothing (tap still opens the details). Height always
/// matches the duration.
private struct BlockCell: View {
    let item: LaneItem
    let past: Bool
    let caffeine: Bool
    var action: () -> Void

    var block: PlanBlock { item.block }

    var body: some View {
        GeometryReader { geo in
            Button(action: action) {
                ZStack(alignment: caffeine ? .top : (geo.size.height < 46 ? .leading : .topLeading)) {
                    RoundedRectangle(cornerRadius: min(10, geo.size.height / 2), style: .continuous).fill(block.kind.fill)
                    if caffeine { caffeineContent } else { mainContent }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibility)
            .accessibilityHint("Shows timing and details")
        }
        .opacity(past ? 0.72 : 1)
    }

    private var icon: some View { KindIcon(kind: block.kind, tint: block.kind.ink).font(.caption2.weight(.semibold)) }

    private var titleRow: some View {
        HStack(spacing: 5) {
            icon
            Text(block.displayTitle).font(.footnote.weight(.medium)).foregroundStyle(block.kind.ink)
                .lineLimit(1).minimumScaleFactor(0.85)
        }
    }

    private var mainContent: some View {
        ViewThatFits(in: .vertical) {
            if let sub = block.displaySubtitle {
                VStack(alignment: .leading, spacing: 2) {
                    titleRow
                    Text(sub).font(.caption2).foregroundStyle(block.kind.ink.opacity(0.8)).lineLimit(1).minimumScaleFactor(0.85)
                }
                .padding(.vertical, 7)
            }
            titleRow.padding(.vertical, 4)
            icon.padding(.vertical, 2)
            Color.clear.frame(height: 0)
        }
        .padding(.horizontal, 9)
    }

    private var caffeineContent: some View {
        ViewThatFits(in: .vertical) {
            VStack(spacing: 4) {
                icon
                Text(block.displayTitle).font(.caption2.weight(.medium)).foregroundStyle(block.kind.ink)
                    .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
            }
            .padding(.vertical, 9)
            icon.padding(.vertical, 2)
            Color.clear.frame(height: 0)
        }
        .padding(.horizontal, 4)
    }

    private var accessibility: String {
        var s = block.displayTitle
        if let sub = block.displaySubtitle { s += ", \(sub)" }
        if block.isOptional { s += ", optional" }
        return s
    }
}

private struct DottedLine: Shape {
    func path(in r: CGRect) -> Path { Path { p in p.move(to: CGPoint(x: r.midX, y: r.minY)); p.addLine(to: CGPoint(x: r.midX, y: r.maxY)) } }
}
