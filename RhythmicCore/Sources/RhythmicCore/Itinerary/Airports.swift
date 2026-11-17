import Foundation

public struct Airport: Codable, Hashable, Sendable {
    public var code: String
    public var city: String
    public var zoneID: String
    public var latitude: Double
    public var longitude: Double
}

/// Airport lookup: IATA → IANA zone + coordinates (for sunrise/sunset).
/// 1. A small hand-checked table (below), which wins where the two disagree.
/// 2. A bundled table of ~7,900 airports generated from github.com/mwgg/Airports (MIT; see
///    Resources/AIRPORTS-LICENSE.txt). Offline; no network.
/// Airports in neither still make the importer ask for the zone instead of guessing.
public enum Airports {
    public static let table: [String: Airport] = Dictionary(uniqueKeysWithValues: rows.map { ($0.code, $0) })

    /// Bundled full table, loaded once on first use.
    public static let extended: [String: Airport] = loadExtended()

    public static func lookup(_ code: String?) -> Airport? {
        guard let code else { return nil }
        let c = code.uppercased()
        return table[c] ?? extended[c]
    }

    static func loadExtended() -> [String: Airport] {
        guard let url = Bundle.module.url(forResource: "airports", withExtension: "tsv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var out: [String: Airport] = [:]
        for line in text.split(separator: "\n") where !line.hasPrefix("#") {
            let f = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard f.count >= 5, let lat = Double(f[2]), let lon = Double(f[3]), TimeZone(identifier: String(f[1])) != nil else { continue }
            let code = String(f[0])
            out[code] = Airport(code: code, city: String(f[4]), zoneID: String(f[1]), latitude: lat, longitude: lon)
        }
        return out
    }

    private static let rows: [Airport] = [
        // Fixture airports
        .init(code: "WDH", city: "Windhoek", zoneID: "Africa/Windhoek", latitude: -22.48, longitude: 17.47),
        .init(code: "ADD", city: "Addis Ababa", zoneID: "Africa/Addis_Ababa", latitude: 8.98, longitude: 38.80),
        .init(code: "SIN", city: "Singapore", zoneID: "Asia/Singapore", latitude: 1.36, longitude: 103.99),
        // Corrections to the bundled table (it lists Seletar under Asia/Kuala_Lumpur; same offset, wrong place)
        .init(code: "XSP", city: "Singapore Seletar", zoneID: "Asia/Singapore", latitude: 1.42, longitude: 103.87),
        .init(code: "EBB", city: "Entebbe", zoneID: "Africa/Kampala", latitude: 0.04, longitude: 32.44),
        // Africa
        .init(code: "JNB", city: "Johannesburg", zoneID: "Africa/Johannesburg", latitude: -26.14, longitude: 28.24),
        .init(code: "CPT", city: "Cape Town", zoneID: "Africa/Johannesburg", latitude: -33.97, longitude: 18.60),
        .init(code: "NBO", city: "Nairobi", zoneID: "Africa/Nairobi", latitude: -1.32, longitude: 36.93),
        .init(code: "LOS", city: "Lagos", zoneID: "Africa/Lagos", latitude: 6.58, longitude: 3.32),
        .init(code: "ACC", city: "Accra", zoneID: "Africa/Accra", latitude: 5.61, longitude: -0.17),
        .init(code: "CAI", city: "Cairo", zoneID: "Africa/Cairo", latitude: 30.12, longitude: 31.41),
        .init(code: "KGL", city: "Kigali", zoneID: "Africa/Kigali", latitude: -1.97, longitude: 30.14),
        .init(code: "DAR", city: "Dar es Salaam", zoneID: "Africa/Dar_es_Salaam", latitude: -6.88, longitude: 39.20),
        .init(code: "LUN", city: "Lusaka", zoneID: "Africa/Lusaka", latitude: -15.33, longitude: 28.45),
        // Middle East / Europe
        .init(code: "DXB", city: "Dubai", zoneID: "Asia/Dubai", latitude: 25.25, longitude: 55.36),
        .init(code: "DOH", city: "Doha", zoneID: "Asia/Qatar", latitude: 25.27, longitude: 51.61),
        .init(code: "IST", city: "Istanbul", zoneID: "Europe/Istanbul", latitude: 41.26, longitude: 28.74),
        .init(code: "LHR", city: "London", zoneID: "Europe/London", latitude: 51.47, longitude: -0.45),
        .init(code: "CDG", city: "Paris", zoneID: "Europe/Paris", latitude: 49.01, longitude: 2.55),
        .init(code: "FRA", city: "Frankfurt", zoneID: "Europe/Berlin", latitude: 50.04, longitude: 8.56),
        .init(code: "AMS", city: "Amsterdam", zoneID: "Europe/Amsterdam", latitude: 52.31, longitude: 4.76),
        .init(code: "MAD", city: "Madrid", zoneID: "Europe/Madrid", latitude: 40.47, longitude: -3.57),
        // Asia / Pacific
        .init(code: "DEL", city: "Delhi", zoneID: "Asia/Kolkata", latitude: 28.56, longitude: 77.10),
        .init(code: "BOM", city: "Mumbai", zoneID: "Asia/Kolkata", latitude: 19.09, longitude: 72.87),
        .init(code: "KTM", city: "Kathmandu", zoneID: "Asia/Kathmandu", latitude: 27.70, longitude: 85.36),
        .init(code: "BKK", city: "Bangkok", zoneID: "Asia/Bangkok", latitude: 13.69, longitude: 100.75),
        .init(code: "KUL", city: "Kuala Lumpur", zoneID: "Asia/Kuala_Lumpur", latitude: 2.75, longitude: 101.71),
        .init(code: "HKG", city: "Hong Kong", zoneID: "Asia/Hong_Kong", latitude: 22.31, longitude: 113.92),
        .init(code: "ICN", city: "Seoul", zoneID: "Asia/Seoul", latitude: 37.46, longitude: 126.44),
        .init(code: "NRT", city: "Tokyo Narita", zoneID: "Asia/Tokyo", latitude: 35.77, longitude: 140.39),
        .init(code: "HND", city: "Tokyo Haneda", zoneID: "Asia/Tokyo", latitude: 35.55, longitude: 139.78),
        .init(code: "SYD", city: "Sydney", zoneID: "Australia/Sydney", latitude: -33.94, longitude: 151.18),
        .init(code: "MEL", city: "Melbourne", zoneID: "Australia/Melbourne", latitude: -37.67, longitude: 144.84),
        .init(code: "ADL", city: "Adelaide", zoneID: "Australia/Adelaide", latitude: -34.95, longitude: 138.53),
        .init(code: "AKL", city: "Auckland", zoneID: "Pacific/Auckland", latitude: -37.01, longitude: 174.79),
        .init(code: "HNL", city: "Honolulu", zoneID: "Pacific/Honolulu", latitude: 21.32, longitude: -157.92),
        // Americas
        .init(code: "JFK", city: "New York", zoneID: "America/New_York", latitude: 40.64, longitude: -73.78),
        .init(code: "EWR", city: "Newark", zoneID: "America/New_York", latitude: 40.69, longitude: -74.17),
        .init(code: "ATL", city: "Atlanta", zoneID: "America/New_York", latitude: 33.64, longitude: -84.43),
        .init(code: "ORD", city: "Chicago", zoneID: "America/Chicago", latitude: 41.98, longitude: -87.90),
        .init(code: "LAX", city: "Los Angeles", zoneID: "America/Los_Angeles", latitude: 33.94, longitude: -118.41),
        .init(code: "SFO", city: "San Francisco", zoneID: "America/Los_Angeles", latitude: 37.62, longitude: -122.38),
        .init(code: "YYZ", city: "Toronto", zoneID: "America/Toronto", latitude: 43.68, longitude: -79.63),
        .init(code: "GRU", city: "São Paulo", zoneID: "America/Sao_Paulo", latitude: -23.43, longitude: -46.47),
        .init(code: "SCL", city: "Santiago", zoneID: "America/Santiago", latitude: -33.39, longitude: -70.79),
    ]

    /// Find the airport whose zone matches, for sun calculations at a non-airport moment.
    public static func representative(forZone zoneID: String) -> Airport? {
        rows.first { $0.zoneID == zoneID }
    }
}
