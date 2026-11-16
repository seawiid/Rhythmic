import SwiftUI
import RhythmicCore

/// Original palette. Every kind also has an icon and a text label, so colour is never the only cue.
extension BlockKind {
    var color: Color {
        switch self {
        case .sleep: Color(light: .init(red: 0.11, green: 0.16, blue: 0.36, alpha: 1), dark: .init(red: 0.36, green: 0.43, blue: 0.80, alpha: 1))
        case .nap: Color(light: .init(red: 0.62, green: 0.58, blue: 0.80, alpha: 1), dark: .init(red: 0.66, green: 0.62, blue: 0.86, alpha: 1))
        case .prioritizeLight: Color(light: .init(red: 0.98, green: 0.80, blue: 0.10, alpha: 1), dark: .init(red: 1.00, green: 0.84, blue: 0.25, alpha: 1))
        case .lightHelpful: Color(light: .init(red: 0.96, green: 0.56, blue: 0.16, alpha: 1), dark: .init(red: 0.98, green: 0.62, blue: 0.28, alpha: 1))
        case .reduceLight: Color(light: .init(red: 0.45, green: 0.47, blue: 0.55, alpha: 1), dark: .init(red: 0.62, green: 0.64, blue: 0.72, alpha: 1))
        case .caffeineOK: Color(light: .init(red: 0.45, green: 0.28, blue: 0.16, alpha: 1), dark: .init(red: 0.76, green: 0.55, blue: 0.38, alpha: 1))
        case .caffeineAvoid: Color(light: .init(red: 0.45, green: 0.28, blue: 0.16, alpha: 1), dark: .init(red: 0.76, green: 0.55, blue: 0.38, alpha: 1))
        case .flight: Color.secondary
        }
    }

    var icon: String {
        switch self {
        case .sleep: "moon.zzz.fill"
        case .nap: "powersleep"
        case .prioritizeLight: "sun.max.fill"
        case .lightHelpful: "sun.min"
        case .reduceLight: "lightbulb.slash"
        case .caffeineOK: "cup.and.saucer.fill"
        case .caffeineAvoid: "cup.and.saucer"
        case .flight: "airplane"
        }
    }

    /// Windows (not continuous instructions) are drawn translucent/outlined.
    var isWindow: Bool { [.nap, .lightHelpful, .caffeineOK].contains(self) }

    var legendLabel: String {
        switch self {
        case .sleep: "Sleep"
        case .nap: "Optional nap window"
        case .prioritizeLight: "Prioritise bright light"
        case .lightHelpful: "Light helpful"
        case .reduceLight: "Reduce light"
        case .caffeineOK: "Caffeine permitted"
        case .caffeineAvoid: "Avoid caffeine"
        case .flight: "Flight"
        }
    }
}

extension Color {
    init(light: UIColor, dark: UIColor) {
        self.init(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

/// Icon with a strike-through for "avoid caffeine".
struct KindIcon: View {
    let kind: BlockKind
    var body: some View {
        Image(systemName: kind.icon)
            .foregroundStyle(kind == .prioritizeLight ? Color.orange : kind.color)
            .overlay {
                if kind == .caffeineAvoid {
                    Rectangle().fill(kind.color).frame(width: 2).rotationEffect(.degrees(-45)).padding(-2)
                }
            }
            .accessibilityHidden(true)
    }
}

enum TimeFmt {
    static func time(_ d: Date, _ zone: String) -> String {
        let f = DateFormatter(); f.timeZone = TimeZone(identifier: zone); f.locale = .current
        f.setLocalizedDateFormatFromTemplate("HHmm")
        return f.string(from: d)
    }

    static func day(_ d: Date, _ zone: String) -> String {
        let f = DateFormatter(); f.timeZone = TimeZone(identifier: zone); f.locale = .current
        f.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return f.string(from: d)
    }

    static func dayTime(_ d: Date, _ zone: String) -> String { "\(day(d, zone)) \(time(d, zone))" }

    static func zoneAbbrev(_ zone: String, at d: Date) -> String {
        TimeZone(identifier: zone)?.abbreviation(for: d) ?? zone
    }

    static func city(_ zone: String) -> String {
        zone.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? zone
    }

    /// "23:10 Mon 23 Nov" in home time, adding the date only when it differs from the local date.
    static func homeReference(_ d: Date, local: String, home: String) -> String? {
        guard local != home, Zone.offsetHours(local, at: d) != Zone.offsetHours(home, at: d) else { return nil }
        // Compact home reference ("⌂ 23:10"), adding the weekday when the home date differs.
        let sameDay = day(d, local) == day(d, home)
        let f = DateFormatter(); f.timeZone = TimeZone(identifier: home); f.locale = .current
        f.setLocalizedDateFormatFromTemplate("EEE")
        return sameDay ? "⌂ \(time(d, home))" : "⌂ \(f.string(from: d)) \(time(d, home))"
    }

    static func duration(_ t: TimeInterval) -> String {
        let m = Int((t / 60).rounded())
        if m < 60 { return "\(m) min" }
        return m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(m % 60) min"
    }
}
