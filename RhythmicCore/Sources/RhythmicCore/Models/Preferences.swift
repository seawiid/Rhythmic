import Foundation

public enum CaffeineHabit: String, Codable, Sendable, CaseIterable {
    /// Doesn't use caffeine: the plan never suggests starting.
    case none
    /// Usually has some caffeine.
    case regular
}

public enum PreTravelShift: String, Codable, Sendable, CaseIterable {
    case off
    /// 30 min/day for the preparation days.
    case gentle
    /// 60 min/day for the preparation days (closest to the CDC suggestion).
    case standard

    public var minutesPerDay: Double {
        switch self { case .off: 0; case .gentle: 30; case .standard: 60 }
    }
}

/// User inputs that personalise the *initial* plan. No logging, no check-ins.
public struct Preferences: Codable, Hashable, Sendable {
    public var homeZoneID: String
    public var bedtime: ClockTime
    public var wakeTime: ClockTime
    /// "I rarely sleep on afternoon flights." When true, main sleep is never planned
    /// on a flight segment that falls in the traveller's biological daytime.
    public var rarelySleepsOnDaytimeFlights: Bool
    public var caffeine: CaffeineHabit
    public var caffeineSensitive: Bool
    public var preTravelShift: PreTravelShift
    public var showHomeTime: Bool

    public init(homeZoneID: String, bedtime: ClockTime, wakeTime: ClockTime,
                rarelySleepsOnDaytimeFlights: Bool = true, caffeine: CaffeineHabit = .regular,
                caffeineSensitive: Bool = false, preTravelShift: PreTravelShift = .gentle, showHomeTime: Bool = true) {
        self.homeZoneID = homeZoneID; self.bedtime = bedtime; self.wakeTime = wakeTime
        self.rarelySleepsOnDaytimeFlights = rarelySleepsOnDaytimeFlights
        self.caffeine = caffeine; self.caffeineSensitive = caffeineSensitive
        self.preTravelShift = preTravelShift; self.showHomeTime = showHomeTime
    }

    /// Habitual sleep opportunity in hours (handles bedtimes after midnight).
    public var sleepHours: Double {
        let m = (wakeTime.minutesSinceMidnight - bedtime.minutesSinceMidnight + 1440) % 1440
        return Double(m == 0 ? 1440 : m) / 60
    }

    /// Demo profile from the product brief — NOT a default for other users.
    public static let demo = Preferences(
        homeZoneID: "Africa/Windhoek", bedtime: ClockTime(22, 0), wakeTime: ClockTime(5, 0),
        rarelySleepsOnDaytimeFlights: true, caffeine: .regular, caffeineSensitive: false,
        preTravelShift: .gentle, showHomeTime: true)
}
