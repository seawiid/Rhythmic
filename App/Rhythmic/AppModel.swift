import Foundation
import Observation
import UserNotifications
import RhythmicCore

@MainActor
@Observable
final class AppModel {
    private(set) var state: AppState
    /// Shown once after an automatic regeneration or when a plan can't be made.
    var notice: String?
    var pendingReminderCount = 0
    /// Real iOS permission, refreshed whenever reminders sync (app launch and each return to foreground).
    var notificationAuthorization: UNAuthorizationStatus = .notDetermined
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
        state.manualSegments + state.feedSegments + state.googleSegments
    }

    /// Upcoming trips only: feeds such as TripIt also contain past trips, which are hidden here.
    var itinerary: NormalizationResult {
        let raw = allImported
        return ItineraryNormalizer.normalize(raw).upcoming(from: raw, now: Date(), keepTripID: state.selectedTripID)
    }

    var upcomingTrips: [Trip] {
        itinerary.trips
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

    func addManual(_ seg: ImportedSegment) {
        state.manualSegments.append(seg)
        reconcilePlan(announce: true); persist()
    }

    /// Deletes the manually added flights in a trip (imported flights would return on the next refresh).
    func removeManualFlights(in trip: Trip) {
        let ids = Set(trip.segments.flatMap(\.sources).filter { $0.kind == .manual }.map(\.externalID))
        state.manualSegments.removeAll { ids.contains($0.source.externalID) }
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
        guard let s = Keychain.get("feed.url"), case .success(let url) = FeedLink.normalize(s) else { return }
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

    /// iOS has refused notifications for Rhythmic (only the user can change this, in Settings).
    var notificationsDenied: Bool { notificationAuthorization == .denied }

    /// Reminders are wanted and iOS allows them. Drives the bell, the preferences toggle and scheduling.
    var remindersActive: Bool {
        state.remindersEnabled && [.authorized, .provisional, .ephemeral].contains(notificationAuthorization)
    }

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
        notificationAuthorization = await NotificationScheduler.shared.authorizationStatus()
        pendingReminderCount = await NotificationScheduler.shared.sync(plan: state.plan, enabled: remindersActive)
    }

    private func persist() { Store.save(state) }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
