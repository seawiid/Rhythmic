import Foundation
import AuthenticationServices
import UIKit
import CryptoKit
import RhythmicCore

// MARK: - Private calendar feed (TripIt or any ICS URL)

/// Fetches an iCalendar feed URL (stored in the Keychain; treat it as a secret).
/// The parser hasn't been validated against a real TripIt feed yet. The review screen
/// shows what was found and what's missing, so nothing is silently assumed.
struct ICSFeedImporter: ItineraryImporter {
    var kind: SourceKind { .tripItFeed }
    var url: URL

    func fetch() async throws -> [ImportedSegment] {
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200, let text = String(data: data, encoding: .utf8) else {
            throw URLError(.badServerResponse)
        }
        return ICSParser.segments(from: text, kind: .tripItFeed)
    }
}

// MARK: - Google Calendar (cloud API)

/// OAuth 2.0 (installed app + PKCE) and read-only Calendar API access.
///
/// STATUS: implemented against Google's documented endpoints but NOT yet exercised against a real
/// account. It needs your own Google Cloud OAuth client ID (iOS type) in Info.plist (`GoogleClientID`)
/// plus the reversed-client-ID URL scheme. Without it the UI shows "Not set up", never "Connected".
///
/// Scopes: read-only events + read-only calendar list, so you can choose which calendars to scan.
/// OAuth grants access to all calendars at that scope; choosing calendars only limits what we read.
/// Device calendars (e.g. subscriptions visible only in a phone app) may not be in the cloud API.
@MainActor
final class GoogleCalendarClient: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let scopes = ["https://www.googleapis.com/auth/calendar.events.readonly",
                         "https://www.googleapis.com/auth/calendar.calendarlist.readonly"]

    struct CalendarInfo: Identifiable, Hashable { var id: String; var name: String; var primary: Bool }

    var clientID: String? {
        let v = Bundle.main.object(forInfoDictionaryKey: "GoogleClientID") as? String
        return (v?.isEmpty == false) ? v : nil
    }
    var isConfigured: Bool { clientID != nil }
    var isSignedIn: Bool { Keychain.get("google.refresh") != nil }

    private var redirectScheme: String? {
        clientID.map { $0.components(separatedBy: ".").reversed().joined(separator: ".") }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
    }

    func signIn() async throws {
        guard let clientID, let scheme = redirectScheme else { throw URLError(.userAuthenticationRequired) }
        let verifier = Self.randomURLSafe(64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        let redirect = "\(scheme):/oauth2redirect"
        var c = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        c.queryItems = [
            .init(name: "client_id", value: clientID), .init(name: "redirect_uri", value: redirect),
            .init(name: "response_type", value: "code"), .init(name: "scope", value: Self.scopes.joined(separator: " ")),
            .init(name: "code_challenge", value: challenge), .init(name: "code_challenge_method", value: "S256"),
        ]
        let callback: URL = try await withCheckedThrowingContinuation { cont in
            let session = ASWebAuthenticationSession(url: c.url!, callbackURLScheme: scheme) { url, error in
                if let url { cont.resume(returning: url) } else { cont.resume(throwing: error ?? URLError(.cancelled)) }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            session.start()
        }
        guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw URLError(.userAuthenticationRequired)
        }
        let tokens = try await tokenRequest(["code": code, "client_id": clientID, "redirect_uri": redirect,
                                             "grant_type": "authorization_code", "code_verifier": verifier])
        if let r = tokens["refresh_token"] as? String { Keychain.set(r, for: "google.refresh") }
        if let a = tokens["access_token"] as? String { accessToken = a }
    }

    func signOut() { Keychain.set(nil, for: "google.refresh"); accessToken = nil }

    private var accessToken: String?

    private func validToken() async throws -> String {
        if let accessToken { return accessToken }
        guard let clientID, let refresh = Keychain.get("google.refresh") else { throw URLError(.userAuthenticationRequired) }
        let t = try await tokenRequest(["client_id": clientID, "refresh_token": refresh, "grant_type": "refresh_token"])
        guard let a = t["access_token"] as? String else { throw URLError(.userAuthenticationRequired) }
        accessToken = a
        return a
    }

    private func tokenRequest(_ form: [String: String]) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = form.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")" }
            .joined(separator: "&").data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: req)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func get(_ path: String, _ query: [URLQueryItem]) async throws -> Data {
        var c = URLComponents(string: "https://www.googleapis.com/calendar/v3" + path)!
        c.queryItems = query
        var req = URLRequest(url: c.url!)
        req.setValue("Bearer \(try await validToken())", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        if (resp as? HTTPURLResponse)?.statusCode == 401 { accessToken = nil; throw URLError(.userAuthenticationRequired) }
        return data
    }

    func calendars() async throws -> [CalendarInfo] {
        struct List: Decodable { struct Item: Decodable { var id: String; var summary: String?; var primary: Bool? }; var items: [Item]? }
        let list = try JSONDecoder().decode(List.self, from: try await get("/users/me/calendarList", []))
        return (list.items ?? []).map { CalendarInfo(id: $0.id, name: $0.summary ?? $0.id, primary: $0.primary ?? false) }
    }

    /// Upcoming events (next 12 months) from the chosen calendars, parsed into raw segments.
    func upcomingSegments(calendarIDs: [String]) async throws -> [ImportedSegment] {
        let iso = ISO8601DateFormatter()
        var out: [ImportedSegment] = []
        for id in calendarIDs {
            var pageToken: String?
            repeat {
                var q: [URLQueryItem] = [
                    .init(name: "timeMin", value: iso.string(from: Date().addingTimeInterval(-2 * 86400))),
                    .init(name: "timeMax", value: iso.string(from: Date().addingTimeInterval(365 * 86400))),
                    .init(name: "singleEvents", value: "true"), .init(name: "showDeleted", value: "true"),
                    .init(name: "maxResults", value: "250"),
                ]
                if let pageToken { q.append(.init(name: "pageToken", value: pageToken)) }
                let enc = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
                let data = try await get("/calendars/\(enc)/events", q)
                out += try GoogleCalendarEventParser.segments(fromEventsListJSON: data)
                pageToken = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["nextPageToken"] as? String
            } while pageToken != nil
        }
        return out
    }

    static func randomURLSafe(_ n: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: n)
        _ = SecRandomCopyBytes(kSecRandomDefault, n, &bytes)
        return Data(bytes).base64URL
    }
}

extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
