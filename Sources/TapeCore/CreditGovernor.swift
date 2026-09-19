import Foundation

/// Persisted counters for the governor. The app backs this with UserDefaults; tests use memory.
public protocol GovernorStore: Sendable {
    func loadMinute() -> GovernorMinute?
    func saveMinute(_ m: GovernorMinute)
    func loadDay() -> GovernorDay?
    func saveDay(_ d: GovernorDay)
}

public struct GovernorMinute: Codable, Equatable, Sendable {
    public var minuteIndex: Int
    public var used: Int
    public init(minuteIndex: Int, used: Int) { self.minuteIndex = minuteIndex; self.used = used }
}

public struct GovernorDay: Codable, Equatable, Sendable {
    public var utcDate: String
    public var used: Int
    public init(utcDate: String, used: Int) { self.utcDate = utcDate; self.used = used }
}

public final class MemoryGovernorStore: GovernorStore, @unchecked Sendable {
    private let lock = NSLock()
    private var minute: GovernorMinute?
    private var day: GovernorDay?
    public init() {}
    public func loadMinute() -> GovernorMinute? { lock.lock(); defer { lock.unlock() }; return minute }
    public func saveMinute(_ m: GovernorMinute) { lock.lock(); minute = m; lock.unlock() }
    public func loadDay() -> GovernorDay? { lock.lock(); defer { lock.unlock() }; return day }
    public func saveDay(_ d: GovernorDay) { lock.lock(); day = d; lock.unlock() }
}

/// Twelve Data Basic plan budget: 8 credits per civil minute, 800 per UTC day.
/// Background work may not touch the last `reserve` credits of the day; user actions may.
///
/// Admission is serialized only for the check-and-spend step. A request that must wait for
/// the next minute releases the gate while it sleeps, so a 1-credit tap is never stuck
/// behind a sleeping 4-credit background poll (Kimi review M3). A request larger than the
/// per-minute limit can never be admitted and fails immediately (Kimi review C1).
public actor CreditGovernor {
    public let limitPerMinute: Int
    public let limitPerDay: Int
    public let reserve: Int
    private let store: GovernorStore
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (TimeInterval) async throws -> Void

    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init(store: GovernorStore,
                limitPerMinute: Int = 8,
                limitPerDay: Int = 800,
                reserve: Int = 40,
                now: @escaping @Sendable () -> Date = { Date() },
                sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64(max(0, $0) * 1_000_000_000)) }) {
        self.store = store
        self.limitPerMinute = limitPerMinute
        self.limitPerDay = limitPerDay
        self.reserve = reserve
        self.now = now
        self.sleep = sleep
    }

    // MARK: counters

    private func minuteIndex() -> Int { Int(now().timeIntervalSince1970 / 60) }

    public func minuteState() -> GovernorMinute {
        let idx = minuteIndex()
        if let m = store.loadMinute(), m.minuteIndex == idx { return m }
        return GovernorMinute(minuteIndex: idx, used: 0)
    }

    public func dayState() -> GovernorDay {
        let d = MarketClock.utcDayString(now())
        if let s = store.loadDay(), s.utcDate == d { return s }
        return GovernorDay(utcDate: d, used: 0)
    }

    /// Credits used today according to the local estimate.
    public var usedToday: Int { dayState().used }

    /// The largest batch that can ever be admitted in one request.
    public var maxBatch: Int { limitPerMinute }

    private enum Verdict { case ok, wait(TimeInterval), dailyCap }

    private func check(cost: Int, userInitiated: Bool) -> Verdict {
        let m = minuteState()
        if m.used + cost > limitPerMinute {
            let nextMinute = TimeInterval((m.minuteIndex + 1) * 60)
            return .wait(max(0.5, nextMinute - now().timeIntervalSince1970 + 0.8))
        }
        let cap = userInitiated ? limitPerDay : limitPerDay - reserve
        if dayState().used + cost > cap { return .dailyCap }
        return .ok
    }

    private func spend(_ cost: Int) {
        var m = minuteState(); m.used += cost; store.saveMinute(m)
        var d = dayState(); d.used += cost; store.saveDay(d)
    }

    /// The service said 429: whatever the local count believes, this minute is full.
    public func markMinuteExhausted() {
        var m = minuteState(); m.used = limitPerMinute; store.saveMinute(m)
    }

    /// Opportunistic: if the service ever exposes `api-credits-used`, trust the larger number.
    public func reconcile(usedThisMinute: Int) {
        var m = minuteState()
        if usedThisMinute > m.used { m.used = usedThisMinute; store.saveMinute(m) }
    }

    // MARK: serial gate (held only across check-and-spend)

    private func enter() async {
        if !busy { busy = true; return }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in waiters.append(c) }
    }

    private func leave() {
        if waiters.isEmpty { busy = false } else { waiters.removeFirst().resume() }
    }

    /// Waits until `cost` credits may be spent, records them, and returns.
    /// Throws `.requestTooLarge` when `cost` exceeds the per-minute limit (never admissible),
    /// `.budgetExhausted` when the daily cap (or the reserve, for background work) would be
    /// crossed, and `.cancelled` if the task is cancelled while waiting.
    public func acquire(cost: Int, userInitiated: Bool) async throws {
        guard cost > 0 else { return }
        guard cost <= limitPerMinute else { throw TapeError.requestTooLarge(cost: cost, limit: limitPerMinute) }
        while true {
            if Task.isCancelled { throw TapeError.cancelled }
            await enter()
            let verdict = check(cost: cost, userInitiated: userInitiated)
            switch verdict {
            case .ok:
                spend(cost)
                leave()
                return
            case .dailyCap:
                leave()
                throw TapeError.budgetExhausted
            case .wait(let seconds):
                leave()
                do { try await sleep(min(seconds, 61)) } catch { throw TapeError.cancelled }
            }
        }
    }

    /// Convenience: acquire, then run the network call.
    public func run<T: Sendable>(cost: Int, userInitiated: Bool, _ work: @Sendable () async throws -> T) async throws -> T {
        try await acquire(cost: cost, userInitiated: userInitiated)
        return try await work()
    }
}

public extension Array where Element == String {
    /// Splits a symbol list into batches the governor can admit (Kimi review C1).
    func chunked(by size: Int) -> [[String]] {
        guard size > 0, !isEmpty else { return isEmpty ? [] : [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
