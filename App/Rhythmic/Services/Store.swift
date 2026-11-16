import Foundation
import Security
import RhythmicCore

/// Everything needed to show the plan and reschedule reminders offline.
struct AppState: Codable {
    var acceptedNotice = false
    var preferences: Preferences?
    var sampleEnabled = false
    var manualSegments: [ImportedSegment] = []
    var feedSegments: [ImportedSegment] = []
    var feedLastFetched: Date?
    var googleSegments: [ImportedSegment] = []
    var googleLastFetched: Date?
    var googleCalendarIDs: [String] = []
    var selectedTripID: String?
    var plan: Plan?
    var remindersEnabled = false
}

/// JSON file in Application Support. Small, atomic, offline.
enum Store {
    static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("rhythmic-state.json")
    }

    static func load() -> AppState {
        guard let data = try? Data(contentsOf: url) else { return AppState() }
        return (try? JSONDecoder().decode(AppState.self, from: data)) ?? AppState()
    }

    static func save(_ state: AppState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

/// Secrets (TripIt private feed URL, Google tokens) live in the Keychain, never in the JSON state.
enum Keychain {
    static let service = "rhythmic"

    static func set(_ value: String?, for key: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service, kSecAttrAccount as String: key]
        SecItemDelete(base as CFDictionary)
        guard let value else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: key, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
}
