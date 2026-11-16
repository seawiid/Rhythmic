import Foundation
import Observation
import RhythmicCore

@MainActor
@Observable
final class AppModel {
    private(set) var state: AppState
    /// Shown once after an automatic regeneration or when a plan can't be made.
    var notice: String?
    var pendingReminderCount = 0
    var isBusy = false
    var importError: String?
    let google = GoogleCalendarClient()

    init() {
        state = Store.load()
        reconcilePlan(announce: true)
    }

    // MARK: Derived

    var preferences: Preferences? { state.preferences }
    var plan: Plan? { state.plan }

    var allImported: [ImportedSegment] {
        (state.sampleEnabled ? Self.sampleSegments : []) + state.manualSegments + state.feedSegments + state.googleSegments
    }

    var itinerary: NormalizationResult { ItineraryNormalizer.normalize(allImported) }

    var upcomingTrips: [Trip] {
        itinerary.trips.filter { $0.arrival > Date().addingTimeInterval(-3 * 86400) || $0.segments.contains { $0.sources.contains { $0.kind == .sample } } }
    }

    var feedURLConfigured: Bool { Keychain.get("feed.url") != nil }

    // MARK: Onboarding & preferences

    func acceptNotice() { state.acceptedNotice = true; persist() }

    func save(preferences p: Preferences) {
        state.preferences = p
        reconcilePlan(announce: state.plan != nil)
        persist()
    }

    // MARK: Sources

    func setSample(_ on: Bool) {
        state.sampleEnabled = on
        if on, state.selectedTripID == nil { state.selectedTripID = Fixtures.namibiaSingapore.segments[0].sampleNormalizedID }
        reconcilePlan(announce: true); persist()
    }

    func addManual(_ seg: ImportedSegment) {
        state.manualSegments.append(seg)
        reconcilePlan(announce: true); persist()
    }

    func removeManual(externalID: String) {
        state.manualSegments.removeAll { $0.source.externalID == externalID }
        reconcilePlan(announce: true); persist()
    }

    func setFeedURL(_ string: String?) {
        Keychain.set(string?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty, for: "feed.url")
        if string == nil { state.feedSegments = []; state.feedLastFetched = nil; reconcilePlan(announce: true); persist() }
    }

    func refreshFeed() async {
        guard let s = Keychain.get("feed.url"), let url = URL(string: s.replacingOccurrences(of: "webcal://", with: "https://")) else { return }
        isBusy = true; defer { isBusy = false }
        do {
            state.feedSegments = try await ICSFeedImporter(url: url).fetch()
            state.feedLastFetched = Date()
            importError = nil
            reconcilePlan(announce: true); persist()
        } catch {
            importError = "Couldn't read the calendar feed. Check the link and your connection. (\(error.localizedDescription))"
        }
    }

    func connectGoogle() async {
        do { try await google.signIn(); importError = nil } catch { importError = "Google sign-in didn't complete. (\(error.localizedDescription))" }
    }

    func setGoogleCalendars(_ ids: [String]) { state.googleCalendarIDs = ids; persist() }

    func refreshGoogle() async {
        guard google.isSignedIn, !state.googleCalendarIDs.isEmpty else { return }
        isBusy = true; defer { isBusy = false }
        do {
            state.googleSegments = try await google.upcomingSegments(calendarIDs: state.googleCalendarIDs)
            state.googleLastFetched = Date()
            importError = nil
            reconcilePlan(announce: true); persist()
        } catch {
            importError = "Couldn't read Google Calendar. (\(error.localizedDescription))"
        }
    }

    func disconnectGoogle() {
        google.signOut(); state.googleSegments = []; state.googleCalendarIDs = []
        reconcilePlan(announce: true); persist()
    }

    // MARK: Plan

    func select(trip: Trip) {
        state.selectedTripID = trip.id
        state.plan = nil
        reconcilePlan(announce: false)
        persist()
    }

    func clearPlan() {
        state.selectedTripID = nil
        state.plan = nil
        persist()
        Task { await syncReminders() }
    }

    /// Regenerate when the itinerary, preferences or rule version changed. Missed-sleep
    /// adjustment is intentionally NOT implemented in v1.
    private func reconcilePlan(announce: Bool) {
        guard let prefs = state.preferences, let tripID = state.selectedTripID else { return }
        let trips = itinerary.trips
        guard let trip = trips.first(where: { $0.id == tripID }) else {
            if state.plan != nil {
                state.plan = nil
                notice = "The selected trip is no longer in your itinerary (cancelled or removed). Its plan and reminders were cleared."
            }
            Task { await syncReminders() }
            return
        }
        if let p = state.plan, p.tripFingerprint == trip.fingerprint, p.preferences == prefs, p.ruleVersion == RuleBook.version { return }
        let hadPlan = state.plan != nil
        let returnTrip = trips.first { $0.departure > trip.arrival && $0.first.origin == trip.last.destination && $0.last.destination == trip.first.origin }
        switch Planner().makePlan(trip: trip, preferences: prefs, returnDeparture: returnTrip?.departure) {
        case .plan(let p):
            state.plan = p
            if hadPlan && announce { notice = "Your itinerary or preferences changed, so the plan was regenerated and reminders were replaced." }
        case .unsupported(let reason):
            state.plan = nil
            notice = reason
        }
        Task { await syncReminders() }
    }

    // MARK: Reminders

    func setReminders(_ on: Bool) async {
        if on {
            let granted = await NotificationScheduler.shared.requestAuthorization()
            state.remindersEnabled = granted
            if !granted { notice = "Notifications are off for Rhythmic. You can turn them on in iOS Settings." }
        } else {
            state.remindersEnabled = false
        }
        persist()
        await syncReminders()
    }

    func syncReminders() async {
        pendingReminderCount = await NotificationScheduler.shared.sync(plan: state.plan, enabled: state.remindersEnabled)
    }

    private func persist() { Store.save(state) }

    // MARK: Sample

    /// The brief's demo itinerary, as raw "imported" records so it flows through the same pipeline.
    static let sampleSegments: [ImportedSegment] = Fixtures.namibiaSingapore.segments.map { s in
        ImportedSegment(source: SourceRef(kind: .sample, externalID: s.id), origin: s.origin, destination: s.destination,
                        departure: .instant(s.departure), arrival: .instant(s.arrival),
                        originZoneID: s.originZoneID, destinationZoneID: s.destinationZoneID,
                        rawSummary: "SAMPLE \(s.origin) → \(s.destination)")
    }
}

extension FlightSegment {
    /// Matches the id the normaliser assigns to the sample's first segment (no flight number).
    var sampleNormalizedID: String {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month, .day], from: departure)
        return "-\(origin)\(destination)-" + String(format: "%04d%02d%02d", c.year!, c.month!, c.day!)
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
