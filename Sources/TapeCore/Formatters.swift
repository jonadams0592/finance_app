import Foundation

/// Number and time formatting shared by the app and the tests. Mirrors the web build:
/// prices under 1.00 get four decimals, everything else two; percentages always two.
public enum Format {
    /// Manual grouping so the output is identical on every platform and needs no shared
    /// formatter instance (NumberFormatter is not Sendable).
    private static func grouped(_ v: Double, precision p: Int) -> String {
        let raw = String(format: "%.\(p)f", v)
        let parts = raw.split(separator: ".", maxSplits: 1).map(String.init)
        var intPart = parts[0]
        let neg = intPart.hasPrefix("-")
        if neg { intPart.removeFirst() }
        var out = ""
        for (i, ch) in intPart.reversed().enumerated() {
            if i > 0 && i % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        let grouped = String(out.reversed())
        return (neg ? "-" : "") + grouped + (parts.count > 1 ? "." + parts[1] : "")
    }

    public static func precision(for value: Double) -> Int {
        let a = abs(value)
        return (a.isFinite && a > 0 && a < 1) ? 4 : 2
    }

    public static func price(_ value: Double?, precision: Int? = nil) -> String {
        guard let v = value, v.isFinite else { return "—" }
        let p = precision ?? Format.precision(for: v)
        return grouped(v, precision: p)
    }

    public static func signed(_ value: Double?, precision: Int? = nil) -> String {
        guard let v = value, v.isFinite else { return "—" }
        let p = precision ?? Format.precision(for: v)
        return (v >= 0 ? "+" : "-") + price(abs(v), precision: p)
    }

    public static func signedPercent(_ value: Double?) -> String {
        guard let v = value, v.isFinite else { return "—" }
        return (v >= 0 ? "+" : "-") + String(format: "%.2f", abs(v)) + "%"
    }

    /// 35660958 -> "35.7M". Manual so it behaves the same on every platform.
    public static func compact(_ value: Double?) -> String {
        guard let v = value, v.isFinite else { return "—" }
        let a = abs(v)
        let sign = v < 0 ? "-" : ""
        func trim(_ x: Double, _ suffix: String) -> String {
            let s = String(format: "%.1f", x)
            let cleaned = s.hasSuffix(".0") ? String(s.dropLast(2)) : s
            return sign + cleaned + suffix
        }
        if a >= 1e12 { return trim(a / 1e12, "T") }
        if a >= 1e9 { return trim(a / 1e9, "B") }
        if a >= 1e6 { return trim(a / 1e6, "M") }
        if a >= 1e3 { return trim(a / 1e3, "K") }
        return sign + String(format: "%.0f", a)
    }

    public static func pad2(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }

    /// Minutes since midnight -> "09:30".
    public static func clock24(minutes: Int) -> String {
        let m = ((minutes % 1440) + 1440) % 1440
        return pad2(m / 60) + ":" + pad2(m % 60)
    }

    public static let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    public static let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    /// "2026-09-17" -> "Sep 17".
    public static func shortDate(_ iso: String) -> String {
        let p = iso.split(separator: "-").compactMap { Int($0) }
        guard p.count >= 3, (1...12).contains(p[1]) else { return iso }
        return monthNames[p[1] - 1] + " " + String(p[2])
    }

    /// "2026-09-17" -> "Thu" (calendar weekday of that date, independent of timezone).
    public static func weekday(_ iso: String) -> String {
        let p = iso.split(separator: "-").compactMap { Int($0) }
        guard p.count >= 3 else { return "" }
        var comps = DateComponents()
        comps.year = p[0]; comps.month = p[1]; comps.day = p[2]; comps.hour = 12
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        guard let d = cal.date(from: comps) else { return "" }
        return dayNames[cal.component(.weekday, from: d) - 1]
    }

    /// "2h 05m", "45m", "3d".
    public static func duration(_ interval: TimeInterval) -> String {
        let m = Int((interval / 60).rounded())
        if m < 60 { return "\(m)m" }
        let h = m / 60
        if h < 48 { return "\(h)h " + pad2(m % 60) + "m" }
        return "\(Int((Double(h) / 24).rounded()))d"
    }
}

/// Helpers for Twelve Data's "YYYY-MM-DD HH:MM:SS" strings (already in exchange time).
public enum BarTime {
    public static func date(of s: String) -> String { String(s.prefix(10)) }
    public static func minutes(of s: String) -> Int {
        guard s.count >= 16 else { return 0 }
        let hh = Int(s[s.index(s.startIndex, offsetBy: 11)..<s.index(s.startIndex, offsetBy: 13)]) ?? 0
        let mm = Int(s[s.index(s.startIndex, offsetBy: 14)..<s.index(s.startIndex, offsetBy: 16)]) ?? 0
        return hh * 60 + mm
    }
}
