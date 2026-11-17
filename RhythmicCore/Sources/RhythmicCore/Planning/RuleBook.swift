import Foundation

/// Evidence metadata for every scheduling rule. Shown behind the optional "Why?" sheet,
/// and mirrored in docs/EVIDENCE.md. Rule *values* live in `RuleParameters`.
public struct Rule: Codable, Hashable, Sendable, Identifiable {
    public enum Basis: String, Codable, Sendable {
        /// Directly supported by the cited guidance/research (still general guidance, not clinical validation).
        case sourceSupported = "Source-supported"
        /// A product default chosen within the range sources discuss; needs expert review.
        case proposedDefault = "Proposed default — needs review"
        /// Engineering simplification needed to make a schedule; not a scientific claim.
        case heuristic = "Heuristic"
    }

    public var id: String
    public var title: String
    public var plainExplanation: String
    public var basis: Basis
    public var sources: [String]
    public var evidenceType: String
    public var assumptions: String
    public var reviewed: String
}

public enum RuleBook {
    public static let version = "rules-2026.11.1"
    static let reviewed = "2026-11-16"

    static let cdc = "CDC Yellow Book 2026, Jet Lag Disorder — https://www.cdc.gov/yellow-book/hcp/travel-air-sea/jet-lag-disorder.html"
    static let eastman2005 = "Eastman et al. 2005, Sleep 28(1) — https://pmc.ncbi.nlm.nih.gov/articles/PMC1249488/"
    static let serkh2014 = "Serkh & Forger 2014, PLOS Comput Biol — https://journals.plos.org/ploscompbiol/article?id=10.1371/journal.pcbi.1003523"
    static let sack2010 = "Circadian travel review (PMC2829880) — https://pmc.ncbi.nlm.nih.gov/articles/PMC2829880/"
    static let gardiner2025 = "Gardiner et al. 2025, Sleep 48(4) — https://pmc.ncbi.nlm.nih.gov/articles/PMC11985402/"
    static let burke2015 = "Burke et al. 2015, Sci Transl Med — https://pmc.ncbi.nlm.nih.gov/articles/PMC4657156/"
    static let fda = "FDA, Spilling the Beans (2024) — https://www.fda.gov/consumers/consumer-updates/spilling-beans-how-much-caffeine-too-much"

    public static let all: [Rule] = [
        Rule(id: "S1", title: "Direction of shift",
             plainExplanation: "Travelling east usually means moving your body clock earlier; west, later. For very large eastward jumps the plan may move your clock later instead, because that can take a similar number of days.",
             basis: .proposedDefault, sources: [cdc, sack2010],
             evidenceType: "Clinical guidance + review; direction threshold is our calculation from CDC population averages",
             assumptions: "Choose the direction with fewer estimated days at 1 h/day (advance) vs 1.5 h/day (delay). Crossover ≈ 9.6 h east. Geography alone is not a validated decision rule; flagged as uncertain for shifts ≥ 10 h.",
             reviewed: reviewed),
        Rule(id: "S2", title: "Short trips and small changes",
             plainExplanation: "For trips shorter than about 2 days, CDC suggests staying on home time. Rhythmic v1 doesn't build that kind of plan yet and will tell you so. Time changes under 2 hours get a simple local-time plan.",
             basis: .sourceSupported, sources: [cdc],
             evidenceType: "Clinical guidance",
             assumptions: "Return detection needs both flights imported. The < 2 h threshold for 'small change' is a proposed default.",
             reviewed: reviewed),
        Rule(id: "C1", title: "Estimated body-clock low point",
             plainExplanation: "Your body clock's low point is estimated as about 3 hours before your usual wake time. It's an estimate from your habits, not a measurement.",
             basis: .heuristic, sources: [cdc],
             evidenceType: "Clinical guidance gives 2–4 h before habitual wake; midpoint used",
             assumptions: "Less reliable with irregular sleep, recent travel, alarms/forced waking.",
             reviewed: reviewed),
        Rule(id: "C2", title: "Estimated adjustment after arrival",
             plainExplanation: "After arrival, the plan assumes an average adjustment of about 1 hour per day when moving earlier and 1.5 hours per day when moving later. Individuals vary; this only positions the light windows.",
             basis: .sourceSupported, sources: [cdc],
             evidenceType: "Clinical guidance (population averages)",
             assumptions: "Not an individual prediction. No adjustment is assumed while travelling.",
             reviewed: reviewed),
        Rule(id: "P1", title: "Shift sleep before you travel",
             plainExplanation: "On the two preparation days, bedtime and wake time move a little toward the destination while keeping your usual amount of sleep.",
             basis: .sourceSupported, sources: [cdc, eastman2005],
             evidenceType: "Clinical guidance (1 h/day for 2–3 days) + small lab study",
             assumptions: "Eastman 2005: 2 h/day gave no significantly larger advance than 1 h/day and worsened some sleep-log measures. Default 30 min/day ('gentle') is a proposed, more conservative choice. The plan assumes the clock follows the sleep shift; that's not guaranteed.",
             reviewed: reviewed),
        Rule(id: "L1", title: "Timing of light",
             plainExplanation: "Light after your body clock's low point moves it earlier; light before it moves it later. So the plan schedules bright light on one side and dimmer light on the other, depending on which way you need to shift.",
             basis: .sourceSupported, sources: [cdc, serkh2014, sack2010],
             evidenceType: "Clinical guidance, review, published model",
             assumptions: "Window widths (4 h prioritise, 3 h helpful, 4 h reduce) are proposed defaults, not validated doses.",
             reviewed: reviewed),
        Rule(id: "L2", title: "Daylight vs bright light",
             plainExplanation: "When the sun is up where you are, the plan suggests daylight outdoors. Otherwise it suggests bright indoor light. A phone or laptop screen is not equivalent to daylight. Never look at the sun, and don't reduce visibility while driving or doing anything safety-critical.",
             basis: .proposedDefault, sources: [cdc, eastman2005],
             evidenceType: "Guidance + lab protocol (intermittent ~5000 lux)",
             assumptions: "30–60 min outdoors is a practical suggestion, not an established equivalent dose. Sunrise/sunset is calculated for the airport location.",
             reviewed: reviewed),
        Rule(id: "L3", title: "Dim light before bed",
             plainExplanation: "Keep lights low in the hour before planned sleep.",
             basis: .proposedDefault, sources: [cdc],
             evidenceType: "General sleep guidance",
             assumptions: "Takes precedence over light-seeking in that hour.",
             reviewed: reviewed),
        Rule(id: "Z1", title: "Protect a realistic sleep opportunity",
             plainExplanation: "Each night keeps your usual sleep length. After arrival, bedtime moves toward local time step by step instead of jumping straight to a bedtime your body isn't ready for.",
             basis: .proposedDefault, sources: [cdc, sack2010],
             evidenceType: "Guidance principle; the step sizes are our defaults",
             assumptions: "Destination sleep may sit up to 2 h (earlier shift) or 3 h (later shift) away from the estimated body clock.",
             reviewed: reviewed),
        Rule(id: "Z2", title: "Sleep on flights",
             plainExplanation: "Because you rarely sleep on daytime flights, the plan doesn't rely on sleeping on a flight during your biological daytime. Main sleep on a flight is only planned during your biological night.",
             basis: .heuristic, sources: [],
             evidenceType: "Personal preference applied before planning",
             assumptions: "Usable flight time excludes the first 30 min after departure and the last 45 min before landing.",
             reviewed: reviewed),
        Rule(id: "Z3", title: "Getting to the airport",
             plainExplanation: "Sleep before a flight ends at least 3 hours before departure.",
             basis: .heuristic, sources: [],
             evidenceType: "Practical assumption",
             assumptions: "3 h for check-in and travel. The first hour after landing is left free for arrival.",
             reviewed: reviewed),
        Rule(id: "N1", title: "Optional short naps",
             plainExplanation: "On long days, the plan shows a window where a short nap (about 20 minutes) is OK. The window is when it's fine to nap, not how long to sleep. Getting enough rest matters more than following the plan exactly.",
             basis: .sourceSupported, sources: [cdc],
             evidenceType: "Clinical guidance (20–30 min naps; longer naps may disrupt night sleep)",
             assumptions: "Offered when a day is at least 1.5 h longer than your usual waking day (and at least 16 h), ending at least 5 h before main sleep. Up to 3 h, placed late in the allowed range. Thresholds are proposed defaults.",
             reviewed: reviewed),
        Rule(id: "K1", title: "Caffeine cutoff",
             plainExplanation: "Caffeine is fine earlier in the day if you already use it. Stop about 8 hours before planned sleep (10 if you're sensitive). 'Permitted' doesn't mean drink continuously.",
             basis: .proposedDefault, sources: [cdc, gardiner2025, fda],
             evidenceType: "Guidance (CDC example: 6 h) + small RCT (n=23 young men: 400 mg disrupted sleep even 12 h before bed; 100 mg showed no significant effect)",
             assumptions: "8 h is more conservative than CDC's 6 h example and isn't a universal safe threshold. Dose matters; FDA's 400 mg/day is a reference for most adults, not a target. Non-users are never told to start.",
             reviewed: reviewed),
        Rule(id: "K2", title: "No caffeine right before a nap",
             plainExplanation: "Caffeine isn't suggested in the hour before an optional nap window.",
             basis: .proposedDefault, sources: [],
             evidenceType: "Product rule",
             assumptions: "Avoids encouraging coffee just because a nap is far from night-time sleep.",
             reviewed: reviewed),
        Rule(id: "K3", title: "Evening caffeine can shift your clock",
             plainExplanation: "Caffeine in the evening has delayed body-clock timing in a small lab study. That's another reason the plan stops caffeine well before bed.",
             basis: .sourceSupported, sources: [burke2015],
             evidenceType: "Small lab study (n=5)",
             assumptions: "No specific shift per cup is modelled.",
             reviewed: reviewed),
    ]

    public static func rule(_ id: String) -> Rule? { all.first { $0.id == id } }
}

/// Numeric parameters for a rule version. Changing any value requires bumping `RuleBook.version`.
public struct RuleParameters: Sendable {
    public var tminHoursBeforeWake = 3.0
    public var advanceRatePerDay = 1.0
    public var delayRatePerDay = 1.5
    public var smallChangeThreshold = 2.0
    public var largeShiftWarning = 10.0
    public var preparationDays = 2
    public var postArrivalDays = 2
    public var advanceSleepAllowance = 2.0
    public var delaySleepAllowance = 3.0
    public var airportBufferHours = 3.0
    public var arrivalBufferHours = 1.0
    public var flightSettleMinutes = 30.0
    public var flightDescentMinutes = 45.0
    public var bodyNightLateExtensionHours = 2.0
    public var napAwakeThresholdHours = 16.0
    public var napExtraAwakeHours = 1.5
    public var napMinGapBeforeSleepHours = 5.0
    public var napWindowMaxHours = 3.0
    public var caffeineCutoffHours = 8.0
    public var caffeineCutoffSensitiveHours = 10.0
    public var caffeineBeforeNapHours = 1.0
    public var windDownHours = 1.0
    public var shortStayDays = 2.0

    public static let current = RuleParameters()
}
