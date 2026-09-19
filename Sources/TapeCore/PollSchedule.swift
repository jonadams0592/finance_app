import Foundation

/// How often the watchlist may refresh so a day of use fits the free plan.
/// Budget model (credits per UTC day, out of 800 with a 40-credit reserve for user actions):
/// - Equities only: ~600 credits spread over the 390-minute session, nothing overnight.
/// - Mixed or 24-hour book: ~400 over the session, ~200 over the other 17.5 hours.
/// When the US market is closed and nothing on the tape trades overnight, the app sleeps
/// until the next 09:30 ET plus one minute (Kimi review C4). A foreground return still
/// refreshes a stale cache; that path is rate-limited to once per 30 minutes.
public enum PollSchedule {
    public static let sessionMinutes = 390.0
    public static let offHoursMinutes = 1050.0
    /// Names the free plan can refresh in one governed batch.
    public static let maxBatch = 8
    /// Largest book the app accepts: two batches, still inside the daily budget at 11 minutes.
    public static let maxSymbols = 16
    /// Consecutive all-failure batches before the book is treated as dead (Kimi review C3).
    public static let deadBookThreshold = 3
    /// Consecutive failures before a single symbol is quarantined (Kimi review C3 / U8).
    public static let quarantineThreshold = 5

    private static func roundedInterval(minutes: Double, credits: Double, symbols: Int, floor: TimeInterval, ceiling: TimeInterval) -> TimeInterval {
        let n = max(1, Double(symbols))
        let polls = max(1, (credits / n).rounded(.down))
        let seconds = (minutes * 60 / polls / 60).rounded(.up) * 60
        return min(ceiling, max(floor, seconds))
    }

    /// Seconds between quote batches. The ceiling rises with the book so a 16-name tape still
    /// fits the day (two 8-name batches every 11 minutes).
    public static func interval(symbols: Int, hasAllDay: Bool, night: Bool) -> TimeInterval {
        if !hasAllDay {
            return roundedInterval(minutes: sessionMinutes, credits: 600, symbols: symbols, floor: 120, ceiling: 900)
        }
        if !night {
            return roundedInterval(minutes: sessionMinutes, credits: 400, symbols: symbols, floor: 120, ceiling: 900)
        }
        return roundedInterval(minutes: offHoursMinutes, credits: 200, symbols: symbols, floor: 600, ceiling: 3600)
    }

    public struct Book: Sendable {
        public var symbols: Int
        public var hasRegularHours: Bool
        public var hasAllDay: Bool
        public init(symbols: Int, hasRegularHours: Bool, hasAllDay: Bool) {
            self.symbols = symbols; self.hasRegularHours = hasRegularHours; self.hasAllDay = hasAllDay
        }
    }

    public struct Health: Sendable {
        public var usMarketOpen: Bool?     // nil until the first batch with a live equity quote answers
        public var limitedBackoffStep: Int // 0 when not rate limited
        public var budgetExhausted: Bool
        public var deadBatches: Int        // consecutive batches with no successful quote at all
        public var keyInvalid: Bool
        public init(usMarketOpen: Bool?, limitedBackoffStep: Int = 0, budgetExhausted: Bool = false, deadBatches: Int = 0, keyInvalid: Bool = false) {
            self.usMarketOpen = usMarketOpen; self.limitedBackoffStep = limitedBackoffStep; self.budgetExhausted = budgetExhausted
            self.deadBatches = deadBatches; self.keyInvalid = keyInvalid
        }
        public var bookIsDead: Bool { deadBatches >= PollSchedule.deadBookThreshold }
    }

    /// Treat an unknown market state as open when the book has equities, so the first
    /// answer arrives promptly; a wrong guess costs one batch. A dead book never counts as open.
    public static func regularHoursOpen(_ health: Health, book: Book) -> Bool {
        if health.bookIsDead { return false }
        if let open = health.usMarketOpen { return open }
        return book.hasRegularHours
    }

    /// First step is a full minute: a 30-second retry lands in the same server minute that
    /// just said 429 (Kimi review M9).
    public static func backoff(step: Int, jitter: Double = 0) -> TimeInterval {
        let bases: [TimeInterval] = [60, 120, 240, 300]
        let base = bases[max(0, min(step, bases.count) - 1)]
        return base * (1 + max(-0.2, min(0.2, jitter)))
    }

    /// Delay until the next background quote batch, or nil when polling should stop entirely.
    public static func nextDelay(book: Book, health: Health, now: Date, clock: MarketClock = .newYork, jitter: Double = 0) -> TimeInterval? {
        if health.keyInvalid || book.symbols == 0 { return nil }
        if health.limitedBackoffStep > 0 { return backoff(step: health.limitedBackoffStep, jitter: jitter) }
        if health.budgetExhausted { return 30 * 60 }
        if health.bookIsDead { return 30 * 60 }
        if regularHoursOpen(health, book: book) { return interval(symbols: book.symbols, hasAllDay: book.hasAllDay, night: false) }
        let wake: TimeInterval = book.hasRegularHours ? clock.nextOpen(after: now).interval + 60 : .infinity
        if book.hasAllDay { return min(interval(symbols: book.symbols, hasAllDay: true, night: true), wake) }
        return wake.isFinite ? wake : nil
    }

    /// Is the cached batch old enough that a wake-up (foreground, focus) should refresh?
    public static func refreshNeeded(lastUpdate: Date?, book: Book, health: Health, now: Date) -> Bool {
        guard let last = lastUpdate else { return true }
        let age = now.timeIntervalSince(last)
        let need: TimeInterval
        if regularHoursOpen(health, book: book) { need = interval(symbols: book.symbols, hasAllDay: book.hasAllDay, night: false) }
        else if book.hasAllDay { need = interval(symbols: book.symbols, hasAllDay: true, night: true) }
        else { need = 30 * 60 }
        return age > need
    }

    /// The quotes are older than two poll intervals while the US market is open, or every
    /// open equity's `last_quote_at` is more than 30 minutes old: the feed, not the market, is stale.
    public static func feedIsStale(lastUpdate: Date?, newestQuoteAt: Date?, book: Book, health: Health, now: Date) -> Bool {
        guard regularHoursOpen(health, book: book), let last = lastUpdate else { return false }
        if now.timeIntervalSince(last) > 2 * interval(symbols: book.symbols, hasAllDay: book.hasAllDay, night: false) + 30 { return true }
        if let q = newestQuoteAt, now.timeIntervalSince(q) > 30 * 60 { return true }
        return false
    }
}
