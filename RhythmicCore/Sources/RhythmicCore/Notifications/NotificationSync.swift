import Foundation

/// Pure reconciliation between what the OS has pending and what the active plan wants.
/// Every Rhythmic notification id starts with `rhythmic.`; anything with that prefix that
/// isn't wanted is removed (plan replaced, disabled, ended, or reminder already past).
public enum NotificationSync {
    public static let prefix = "rhythmic."

    public struct Diff: Equatable, Sendable {
        public var remove: [String]
        public var add: [PlanTransition]
    }

    public static func diff(pendingIDs: [String], desired: [PlanTransition]) -> Diff {
        let desiredIDs = Set(desired.map(\.id))
        let ours = pendingIDs.filter { $0.hasPrefix(prefix) }
        let remove = ours.filter { !desiredIDs.contains($0) }.sorted()
        let pending = Set(ours)
        return Diff(remove: remove, add: desired.filter { !pending.contains($0.id) })
    }
}
