import Foundation

public enum BlockKind: String, Codable, Sendable, CaseIterable {
    case sleep            // main sleep opportunity
    case nap              // optional nap WINDOW (see recommendedMinutes)
    case prioritizeLight  // yellow
    case lightHelpful     // orange
    case reduceLight      // outlined / dimmed
    case caffeineOK       // caffeine permitted window (not "drink continuously")
    case caffeineAvoid    // crossed-out
    case flight           // context, not a recommendation

    public var lane: Lane {
        switch self {
        case .sleep, .nap: .sleep
        case .prioritizeLight, .lightHelpful, .reduceLight: .light
        case .caffeineOK, .caffeineAvoid: .caffeine
        case .flight: .context
        }
    }

    public enum Lane: String, Codable, Sendable, CaseIterable { case sleep, light, caffeine, context }
}

public enum PlanPhase: String, Codable, Sendable { case preparation, travel, destination }

public struct PlanBlock: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var kind: BlockKind
    public var start: Date
    public var end: Date
    public var title: String
    /// Short practical instruction shown in the timeline.
    public var detail: String
    /// For windows: a recommended duration *within* the window (e.g. nap 20 min, light 30–60 min).
    public var recommendedMinutes: ClosedRange<Int>?
    public var isOptional: Bool
    /// IDs into `RuleBook` for the optional "Why?" explanation.
    public var ruleIDs: [String]
    /// IANA zone used for "local" display of this block.
    public var zoneID: String
    /// Set when the block happens on a flight segment.
    public var segmentID: String?

    public var span: TimeSpan { TimeSpan(start, end) }
}

public struct PlanWarning: Codable, Hashable, Sendable {
    /// `info` and `caution` live in the plan's details; only `critical` is shown on the plan screen.
    public enum Severity: String, Codable, Sendable { case info, caution, critical }
    public var severity: Severity
    public var message: String
}

public enum ShiftDirection: String, Codable, Sendable { case advance, delay, none }

public struct PlanStrategy: Codable, Hashable, Sendable {
    /// Destination minus home UTC offset, normalised to (-12, 12].
    public var zoneDifferenceHours: Double
    public var direction: ShiftDirection
    /// Total intended body-clock shift in hours (positive number).
    public var shiftHours: Double
    /// Estimated remaining misalignment at plan end (population-average model; not a measurement).
    public var estimatedResidualAtEndHours: Double
}

/// A transition worth a notification (computed separately from the timeline).
public struct PlanTransition: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var date: Date
    public var title: String
    public var body: String
}

public struct Plan: Codable, Hashable, Sendable, Identifiable {
    /// Deterministic: same trip + preferences + rule version ⇒ same id.
    public var id: String
    public var ruleVersion: String
    public var tripID: String
    public var tripFingerprint: String
    public var preferences: Preferences
    public var trip: Trip
    public var horizon: TimeSpan
    public var strategy: PlanStrategy
    public var blocks: [PlanBlock]
    public var warnings: [PlanWarning]

    public func blocks(at date: Date) -> [PlanBlock] {
        blocks.filter { $0.span.contains(date) }
    }

    public func phase(at date: Date) -> PlanPhase {
        if date < trip.departure.adding(hours: -3) { return .preparation }
        if date < trip.arrival { return .travel }
        return .destination
    }

    public var homeZoneID: String { preferences.homeZoneID }
}

public enum PlanResult: Sendable {
    case plan(Plan)
    /// Outside supported rules: we say so instead of producing falsely precise guidance.
    case unsupported(reason: String)
}
