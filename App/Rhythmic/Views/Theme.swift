import SwiftUI
import UIKit
import RhythmicCore

// MARK: - Palette
// Cool, minimal and solid. Every block kind also has an icon and a title, so colour is never the only cue.

private func rgb(_ hex: UInt32) -> UIColor {
    UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

extension Color {
    init(light: UIColor, dark: UIColor) {
        self.init(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
    init(_ light: UInt32, _ dark: UInt32) { self.init(light: rgb(light), dark: rgb(dark)) }
}

enum Palette {
    static let background = Color(0xF5F6F8, 0x121316)
    static let surface = Color(0xFFFFFF, 0x1C1D21)
    static let line = Color(0xE4E6EA, 0x2D2F35)
    static let ink = Color(0x1F2633, 0xECEFF4)
    static let secondary = Color(0x6B7280, 0x9EA5B2)
    /// Location labels and links.
    static let accent = Color(0x3B6D9B, 0x8DB6DE)
    static let now = Color(0xC2412D, 0xF08A6E)
    /// Neutral icon on the current-action card.
    static let cardIcon = Color(0x475569, 0xCBD5E1)
    /// The ring in the wordmark and app icon.
    static let brand = Color(0xCBA65B, 0xD9B872)
}

// MARK: - Wordmark
/// "Rhythmic" with a small gold ring at cap height, matching the app icon's "R°".
struct Wordmark: View {
    @ScaledMetric(relativeTo: .title2) private var ring: CGFloat = 9.5
    @ScaledMetric(relativeTo: .title2) private var stroke: CGFloat = 2.8
    private var capHeight: CGFloat { UIFont.preferredFont(forTextStyle: .title2).capHeight }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: ring * 0.3) {
            Text("Rhythmic").font(.title2.weight(.semibold)).kerning(-0.5).foregroundStyle(Palette.ink)
            Circle().strokeBorder(Palette.brand, lineWidth: stroke)
                .frame(width: ring, height: ring)
                // Top of the ring sits on the cap line.
                .alignmentGuide(.firstTextBaseline) { d in d[.top] + capHeight }
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rhythmic")
    }
}

extension BlockKind {
    var fill: Color {
        switch self {
        case .sleep: Color(0x2F3B5C, 0x34426A)
        case .prioritizeLight: Color(0xF4D46C, 0xE6C55C)
        case .lightHelpful: Color(0xF8DDB5, 0x8A5B34)
        case .nap: Color(0xE3E2F1, 0x3D405E)
        case .reduceLight: Color(0xE5E7EB, 0x2B2E35)
        case .caffeineOK: Color(0xEADCCB, 0x4A3E31)
        case .caffeineAvoid: Color(0xF0EFED, 0x23262C)
        case .flight: Palette.line
        }
    }

    var ink: Color {
        switch self {
        case .sleep: Color(0xF3F5FB, 0xEEF1FA)
        case .prioritizeLight: Color(0x3F3110, 0x2E2408)
        case .lightHelpful: Color(0x4A3519, 0xFCEBD6)
        case .nap: Color(0x3B3D5C, 0xE3E3F5)
        case .reduceLight: Color(0x3D4450, 0xC9CED8)
        case .caffeineOK: Color(0x6E5236, 0xE9D3B4)
        case .caffeineAvoid: Color(0x7A7F87, 0x9AA0AA)
        case .flight: Palette.secondary
        }
    }

    /// Accent used for small icons outside a block (detail sheets).
    var color: Color {
        switch self {
        case .prioritizeLight: Color(0xC9961A, 0xF0CF5E)
        case .lightHelpful: Color(0xC97A2B, 0xF2B575)
        case .sleep: Color(0x2F3B5C, 0x8E9CD0)
        case .nap: Color(0x7472A6, 0xB4B2E0)
        case .caffeineOK, .caffeineAvoid: Color(0x8A6845, 0xD8B98F)
        case .reduceLight, .flight: Palette.secondary
        }
    }

    var icon: String {
        switch self {
        case .sleep: "moon.fill"
        case .nap: "powersleep"
        case .prioritizeLight: "sun.max.fill"
        case .lightHelpful: "sun.min"
        case .reduceLight: "lamp.desk"
        case .caffeineOK: "cup.and.saucer.fill"
        case .caffeineAvoid: "cup.and.saucer"
        case .flight: "airplane"
        }
    }

    var legendLabel: String {
        switch self {
        case .sleep: "Sleep"
        case .nap: "Optional nap window"
        case .prioritizeLight: "Prioritize light"
        case .lightHelpful: "Light helpful"
        case .reduceLight: "Keep light low"
        case .caffeineOK: "Coffee OK"
        case .caffeineAvoid: "No caffeine"
        case .flight: "Flight"
        }
    }
}

extension PlanBlock {
    /// Short timeline title.
    var displayTitle: String {
        switch kind {
        case .prioritizeLight: "Prioritize light"
        case .lightHelpful: "Light helpful"
        case .nap: segmentID != nil ? "Optional rest" : "Optional nap"
        case .reduceLight: "Keep light low"
        case .sleep: "Sleep"
        case .caffeineOK: "Coffee OK"
        case .caffeineAvoid: "No caffeine"
        case .flight: title
        }
    }

    /// At most one short line, derived from the planner's existing text. Never repeats the time
    /// range (the timeline already shows it). Caffeine blocks have none.
    var displaySubtitle: String? {
        switch kind {
        case .prioritizeLight:
            switch title {
            case "Get daylight": return recommendedMinutes.map { "\($0.lowerBound)–\($0.upperBound) min outdoors" } ?? "Outdoors"
            case "Bright light": return "Bright indoor light"
            case "Seek light": return "Shade open, reading light on"
            default: return nil
            }
        case .nap: return recommendedMinutes.map { "\($0.lowerBound)–\($0.upperBound) min, if you need it" }
        case .reduceLight:
            if title == "Wind down" { return "Wind down" }
            return segmentID != nil ? "Shade down, eye mask" : nil
        case .sleep: return segmentID != nil ? "On the flight" : nil
        case .lightHelpful, .caffeineOK, .caffeineAvoid, .flight: return nil
        }
    }
}

/// Small icon in a kind's accent colour, with a strike-through for "no caffeine".
struct KindIcon: View {
    let kind: BlockKind
    var tint: Color?
    var body: some View {
        Image(systemName: kind.icon)
            .foregroundStyle(tint ?? kind.color)
            .overlay {
                if kind == .caffeineAvoid {
                    Rectangle().fill(tint ?? kind.color).frame(width: 1.5).rotationEffect(.degrees(-45)).padding(-1)
                }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Appearance

enum AppearanceMode: String, CaseIterable, Identifiable {
    case light, dark, system
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var style: UIUserInterfaceStyle {
        switch self { case .light: .light; case .dark: .dark; case .system: .unspecified }
    }

    static let storageKey = "appearance"

    /// Applied to every window (sheets included). `.unspecified` follows the device setting live.
    @MainActor func apply() {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows { window.overrideUserInterfaceStyle = style }
        }
    }
}

// MARK: - Formatting

enum TimeFmt {
    private static func formatter(_ template: String, _ zone: String) -> DateFormatter {
        let f = DateFormatter(); f.timeZone = TimeZone(identifier: zone); f.locale = .current
        f.setLocalizedDateFormatFromTemplate(template)
        return f
    }

    static func time(_ d: Date, _ zone: String) -> String { formatter("HHmm", zone).string(from: d) }
    static func day(_ d: Date, _ zone: String) -> String { formatter("EEEdMMM", zone).string(from: d) }
    static func weekday(_ d: Date, _ zone: String) -> String { formatter("EEE", zone).string(from: d) }
    static func dayTime(_ d: Date, _ zone: String) -> String { "\(day(d, zone)) \(time(d, zone))" }
    static func shortDate(_ d: Date, _ zone: String) -> String { formatter("dMMM", zone).string(from: d) }

    static func zoneAbbrev(_ zone: String, at d: Date) -> String {
        TimeZone(identifier: zone)?.abbreviation(for: d) ?? zone
    }

    static func city(_ zone: String) -> String { TimelineLayout.cityName(zone) }

    static func duration(_ t: TimeInterval) -> String {
        let m = Int((t / 60).rounded())
        if m < 60 { return "\(m) min" }
        return m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(m % 60) min"
    }

    /// Time in the plan's clock zone, with the weekday when it isn't on `reference`'s local date.
    static func clock(_ d: Date, trip: Trip, relativeTo reference: Date) -> String {
        let z = trip.clockZoneID(at: d)
        let sameDay = day(d, z) == day(reference, trip.clockZoneID(at: reference))
        return sameDay ? time(d, z) : "\(weekday(d, z)) \(time(d, z))"
    }

    /// "23–24 Nov" for a trip, in each end's local time.
    static func tripDates(_ trip: Trip) -> String {
        let a = shortDate(trip.departure, trip.originZoneID), b = shortDate(trip.arrival, trip.destinationZoneID)
        return a == b ? a : "\(a) – \(b)"
    }
}

extension Trip {
    /// "Windhoek → Singapore", using airport cities where known.
    var cityTitle: String {
        "\(Airports.lookup(first.origin)?.city ?? first.origin) → \(Airports.lookup(last.destination)?.city ?? last.destination)"
    }

    /// "Via Addis Ababa" for connections.
    var viaText: String? {
        func city(_ c: String) -> String { Airports.lookup(c)?.city ?? c }
        let stops = zip(segments, segments.dropFirst()).map { a, b in
            a.destination == b.origin ? city(a.destination) : "\(city(a.destination)) / \(city(b.origin))"
        }
        return stops.isEmpty ? nil : "Via " + stops.joined(separator: ", ")
    }
}
