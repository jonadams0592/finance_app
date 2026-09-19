import Foundation

/// New York trading clock. Holidays are not modelled: a poll on a holiday gets
/// `is_market_open == false` from the quote and the schedule goes back to sleep.
public struct MarketClock: Sendable {
    /// Only the identifier is stored: `TimeZone` and `Calendar` are not `Sendable` on
    /// swift-corelibs-foundation, and the clock is a value that crosses actors.
    public let timeZoneIdentifier: String

    public static let newYork = MarketClock(timeZoneIdentifier: "America/New_York")

    public init(timeZoneIdentifier: String) {
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    public var timeZone: TimeZone { TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(secondsFromGMT: -4 * 3600)! }

    public var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal
    }

    /// "YYYY-MM-DD" for the given instant in New York.
    public func dayString(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// "YYYY-MM-DD" in UTC, the day Twelve Data resets the daily credit allowance (00:00 UTC).
    public static func utcDayString(_ date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public struct NextOpen: Equatable, Sendable {
        public let interval: TimeInterval
        public let weekday: String
        public let sameDay: Bool
    }

    /// Time until the next weekday 09:30 New York.
    public func nextOpen(after date: Date) -> NextOpen {
        let c = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        let dow = (c.weekday ?? 1) - 1 // 0 = Sunday
        let nowMin = dow * 1440 + (c.hour ?? 0) * 60 + (c.minute ?? 0)
        for k in 0...7 {
            let day = (dow + k) % 7
            if day == 0 || day == 6 { continue }
            let t = (dow + k) * 1440 + 570
            if t > nowMin {
                return NextOpen(interval: TimeInterval((t - nowMin) * 60), weekday: Format.dayNames[day], sameDay: k == 0)
            }
        }
        return NextOpen(interval: 24 * 3600, weekday: "Mon", sameDay: false)
    }
}
