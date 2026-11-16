import Foundation

/// NOAA-style approximate solar position (±~1–2 min for sunrise/sunset), used only to
/// choose between "daylight outdoors" and "bright indoor light".
public enum Solar {
    /// Solar elevation in degrees at an instant and location.
    public static func elevation(at date: Date, latitude: Double, longitude: Double) -> Double {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .hour, .minute, .second], from: date)
        let dayOfYear = Double(cal.ordinality(of: .day, in: .year, for: date) ?? 1)
        let hours = Double(c.hour!) + Double(c.minute!) / 60 + Double(c.second!) / 3600
        let γ = 2 * Double.pi / 365 * (dayOfYear - 1 + (hours - 12) / 24)
        let eqTime = 229.18 * (0.000075 + 0.001868 * cos(γ) - 0.032077 * sin(γ) - 0.014615 * cos(2 * γ) - 0.040849 * sin(2 * γ))
        let decl = 0.006918 - 0.399912 * cos(γ) + 0.070257 * sin(γ) - 0.006758 * cos(2 * γ)
            + 0.000907 * sin(2 * γ) - 0.002697 * cos(3 * γ) + 0.00148 * sin(3 * γ)
        let trueSolarMinutes = hours * 60 + eqTime + 4 * longitude
        let hourAngle = (trueSolarMinutes / 4 - 180) * Double.pi / 180
        let lat = latitude * Double.pi / 180
        let cosZenith = sin(lat) * sin(decl) + cos(lat) * cos(decl) * cos(hourAngle)
        return 90 - acos(max(-1, min(1, cosZenith))) * 180 / Double.pi
    }

    public static func isDaylight(at date: Date, latitude: Double, longitude: Double) -> Bool {
        elevation(at: date, latitude: latitude, longitude: longitude) > -0.833
    }

    /// Split a span at sunrise/sunset (5-minute resolution).
    public static func splitByDaylight(_ span: TimeSpan, latitude: Double, longitude: Double) -> [(TimeSpan, Bool)] {
        var out: [(TimeSpan, Bool)] = []
        var segStart = span.start
        var state = isDaylight(at: segStart, latitude: latitude, longitude: longitude)
        var t = span.start.adding(minutes: 5)
        while t < span.end {
            let s = isDaylight(at: t, latitude: latitude, longitude: longitude)
            if s != state {
                out.append((TimeSpan(segStart, t), state))
                segStart = t; state = s
            }
            t = t.adding(minutes: 5)
        }
        out.append((TimeSpan(segStart, span.end), state))
        // Absorb slivers (< 20 min) into the neighbouring piece to avoid noisy timelines.
        var merged: [(TimeSpan, Bool)] = []
        for piece in out {
            if let last = merged.last, piece.0.duration < 20 * 60 {
                merged[merged.count - 1] = (TimeSpan(last.0.start, piece.0.end), last.1)
            } else if let last = merged.last, last.0.duration < 20 * 60 {
                merged[merged.count - 1] = (TimeSpan(last.0.start, piece.0.end), piece.1)
            } else {
                merged.append(piece)
            }
        }
        return merged
    }
}
