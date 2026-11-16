import Foundation
import UserNotifications
import RhythmicCore

/// Schedules plan reminders as local notifications. They're stored by iOS and fire offline.
///
/// Honest limits (also shown in the UI):
/// - These are ordinary notifications, not alarms. Silent mode, Focus and notification settings can hide them.
/// - iOS keeps at most 64 pending per app; we schedule the next 60 and top up whenever the app opens.
/// - Triggers are absolute time intervals, so phone time-zone changes during travel don't shift them.
final class NotificationScheduler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationScheduler()
    private let center = UNUserNotificationCenter.current()

    func install() { center.delegate = self }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// Reconcile pending OS notifications with the plan. Removes every stale Rhythmic reminder
    /// (old plan, disabled, ended) and adds missing ones. Returns how many are now pending.
    @discardableResult
    func sync(plan: Plan?, enabled: Bool, now: Date = Date()) async -> Int {
        let desired = plan.map { NotificationPlanner().pending(for: $0, now: now, enabled: enabled) } ?? []
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        let diff = NotificationSync.diff(pendingIDs: pending, desired: desired)
        center.removePendingNotificationRequests(withIdentifiers: diff.remove)
        for t in diff.add {
            let interval = t.date.timeIntervalSince(now)
            guard interval > 1 else { continue }
            let content = UNMutableNotificationContent()
            content.title = t.title
            content.body = t.body
            content.sound = .default
            content.threadIdentifier = "rhythmic-plan"
            let req = UNNotificationRequest(identifier: t.id, content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false))
            try? await center.add(req)
        }
        return await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix(NotificationSync.prefix) }.count
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
