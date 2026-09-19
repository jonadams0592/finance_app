import XCTest
@testable import TapeCore

final class FormatTests: XCTestCase {
    func testPricePrecision() {
        XCTAssertEqual(Format.price(337.0), "337.00")
        XCTAssertEqual(Format.price(81364.01), "81,364.01")
        XCTAssertEqual(Format.price(0.2510), "0.2510")
        XCTAssertEqual(Format.price(nil), "—")
        XCTAssertEqual(Format.signed(0.2510, precision: 2), "+0.25")
        XCTAssertEqual(Format.signed(-1.41), "-1.41")
        XCTAssertEqual(Format.signedPercent(0.2), "+0.20%")
        XCTAssertEqual(Format.signedPercent(-0.99), "-0.99%")
        XCTAssertEqual(Format.price(1_234_567.891), "1,234,567.89")
        XCTAssertEqual(Format.price(-0.5), "-0.5000")
        XCTAssertEqual(Format.price(999), "999.00")
        XCTAssertEqual(Format.price(1000), "1,000.00")
        XCTAssertEqual(Format.price(Double.nan), "—")
    }

    func testCompact() {
        XCTAssertEqual(Format.compact(35_660_958), "35.7M")
        XCTAssertEqual(Format.compact(44_230_970), "44.2M")
        XCTAssertEqual(Format.compact(1_000), "1K")
        XCTAssertEqual(Format.compact(950), "950")
    }

    func testClockAndDates() {
        XCTAssertEqual(Format.clock24(minutes: 570), "09:30")
        XCTAssertEqual(Format.clock24(minutes: 960), "16:00")
        XCTAssertEqual(Format.shortDate("2026-09-17"), "Sep 17")
        XCTAssertEqual(Format.weekday("2026-09-17"), "Thu")
        XCTAssertEqual(Format.weekday("2026-09-19"), "Sat")
        XCTAssertEqual(BarTime.minutes(of: "2026-09-17 15:55:00"), 955)
        XCTAssertEqual(BarTime.date(of: "2026-09-17 15:55:00"), "2026-09-17")
    }
}

final class MarketClockTests: XCTestCase {
    private let iso = ISO8601DateFormatter()

    func testNextOpenFromSaturday() {
        // Saturday 10:00 ET = 14:00 UTC
        let sat = iso.date(from: "2026-09-19T14:00:00Z")!
        let next = MarketClock.newYork.nextOpen(after: sat)
        XCTAssertEqual(next.weekday, "Mon")
        XCTAssertFalse(next.sameDay)
        XCTAssertEqual(next.interval, TimeInterval((47 * 60 + 30) * 60), accuracy: 1)
    }

    func testNextOpenSameDayBeforeBell() {
        // Friday 08:00 ET = 12:00 UTC
        let fri = iso.date(from: "2026-09-18T12:00:00Z")!
        let next = MarketClock.newYork.nextOpen(after: fri)
        XCTAssertTrue(next.sameDay)
        XCTAssertEqual(next.interval, 90 * 60, accuracy: 1)
    }

    func testDayStrings() {
        let d = iso.date(from: "2026-09-19T01:00:00Z")! // Friday 21:00 ET
        XCTAssertEqual(MarketClock.newYork.dayString(d), "2026-09-18")
        XCTAssertEqual(MarketClock.utcDayString(d), "2026-09-19")
    }
}

final class SeriesParserTests: XCTestCase {
    private func bars(_ specs: [(String, Double)]) -> [Bar] {
        specs.reversed().map { Bar(datetime: $0.0, close: $0.1) } // newest first, like the API
    }

    func testRegularDayFiltersToLatestSessionAndSlots() {
        let b = bars([("2026-09-16 15:55:00", 1), ("2026-09-17 09:30:00", 10), ("2026-09-17 12:00:00", 11), ("2026-09-17 16:00:00", 12)])
        let s = SeriesParser.parse(bars: b, timeframe: .day, session: .regularHours)!
        XCTAssertEqual(s.sessionDate, "2026-09-17")
        XCTAssertEqual(s.points.map(\.slot), [0, 30, 78])
        XCTAssertEqual(s.points.first?.label, "09:30")
        XCTAssertEqual(s.slots, 78)
        XCTAssertEqual(SeriesParser.regularAxis(for: s, slots: 78).map(\.text), ["09:30", "11:00", "12:30", "14:00", "16:00"])
    }

    func testEarlyCloseShrinksAxis() {
        var specs: [(String, Double)] = []
        var m = 570
        while m <= 780 { specs.append(("2026-09-17 \(Format.clock24(minutes: m)):00", 25)); m += 5 }
        let s = SeriesParser.parse(bars: bars(specs), timeframe: .day, session: .regularHours)!
        let slots = SeriesParser.effectiveSlots(for: s, sessionComplete: true)
        XCTAssertEqual(slots, 42)
        XCTAssertEqual(SeriesParser.regularAxis(for: s, slots: slots).map(\.text), ["09:30", "11:00", "13:00"])
        XCTAssertEqual(SeriesParser.effectiveSlots(for: s, sessionComplete: false), 78)
    }

    func testWeekClampsTheClosingBar() {
        let b = bars([("2026-09-15 09:30:00", 1), ("2026-09-15 16:00:00", 2), ("2026-09-16 09:30:00", 3)])
        let s = SeriesParser.parse(bars: b, timeframe: .week, session: .regularHours)!
        XCTAssertEqual(s.days, ["2026-09-15", "2026-09-16"])
        XCTAssertEqual(s.slots, 26)
        XCTAssertEqual(s.points.map(\.slot), [0, 12, 13])
    }

    func testAllDayAxis() {
        var specs: [(String, Double)] = []
        for i in 0..<96 {
            let total = 14 * 60 + 15 + i * 15 - 24 * 60 // start 14:15 the day before
            let day = total < 0 ? "2026-09-17" : "2026-09-18"
            specs.append(("\(day) \(Format.clock24(minutes: total)):00", Double(100 + i)))
        }
        let s = SeriesParser.parse(bars: bars(specs), timeframe: .day, session: .allDay)!
        XCTAssertEqual(s.profile, .allDay)
        XCTAssertEqual(s.points.count, 96)
        XCTAssertEqual(s.slots, 95)
        XCTAssertEqual(s.axis?.first?.text, "14:15")
        XCTAssertEqual(s.axis?.last?.text, "14:00")
        XCTAssertEqual(s.axis?.count, 5)
    }
}

final class PollScheduleTests: XCTestCase {
    func testIntervals() {
        XCTAssertEqual(PollSchedule.interval(symbols: 4, hasAllDay: false, night: false), 180)
        XCTAssertEqual(PollSchedule.interval(symbols: 6, hasAllDay: false, night: false), 240)
        XCTAssertEqual(PollSchedule.interval(symbols: 1, hasAllDay: false, night: false), 120)
        XCTAssertEqual(PollSchedule.interval(symbols: 10, hasAllDay: false, night: false), 420)
        XCTAssertEqual(PollSchedule.interval(symbols: 16, hasAllDay: false, night: false), 660)
        XCTAssertEqual(PollSchedule.interval(symbols: 3, hasAllDay: true, night: true), 960)
        XCTAssertEqual(PollSchedule.interval(symbols: 2, hasAllDay: true, night: false), 120)
    }

    func testDailyBudgetFits() {
        // Equities only, six names: 390 minutes at 240s + nothing overnight.
        let perDay = (390 * 60 / PollSchedule.interval(symbols: 6, hasAllDay: false, night: false)) * 6
        XCTAssertLessThan(perDay, 760)
        // Mixed book of three: session share plus overnight share stays under the reserve line.
        let rth = (390 * 60 / PollSchedule.interval(symbols: 3, hasAllDay: true, night: false)) * 3
        let night = (1050 * 60 / PollSchedule.interval(symbols: 3, hasAllDay: true, night: true)) * 3
        XCTAssertLessThan(rth + night, 760)
    }

    func testNextDelayWhenClosedSleepsUntilTheBell() {
        let iso = ISO8601DateFormatter()
        let sat = iso.date(from: "2026-09-19T14:00:00Z")!
        let equities = PollSchedule.Book(symbols: 4, hasRegularHours: true, hasAllDay: false)
        let closed = PollSchedule.Health(usMarketOpen: false)
        // Equities only: no overnight heartbeat, wake one minute after Monday's open (Kimi C4)
        XCTAssertEqual(PollSchedule.nextDelay(book: equities, health: closed, now: sat)!, TimeInterval((47 * 60 + 30) * 60 + 60), accuracy: 1)
        let mixed = PollSchedule.Book(symbols: 3, hasRegularHours: true, hasAllDay: true)
        XCTAssertEqual(PollSchedule.nextDelay(book: mixed, health: closed, now: sat), 960)
        let limited = PollSchedule.Health(usMarketOpen: true, limitedBackoffStep: 1)
        XCTAssertEqual(PollSchedule.nextDelay(book: equities, health: limited, now: sat), 60)
        // A bad key stops the loop outright (Kimi M1)
        XCTAssertNil(PollSchedule.nextDelay(book: equities, health: PollSchedule.Health(usMarketOpen: true, keyInvalid: true), now: sat))
        // Crypto only, nothing to wake for: night interval
        let crypto = PollSchedule.Book(symbols: 2, hasRegularHours: false, hasAllDay: true)
        XCTAssertEqual(PollSchedule.nextDelay(book: crypto, health: PollSchedule.Health(usMarketOpen: nil), now: sat), 660)
    }

    func testDeadBookFallsOffTheSessionRate() {
        // Three all-failure batches: the book is no longer treated as "open" (Kimi C3)
        let book = PollSchedule.Book(symbols: 4, hasRegularHours: true, hasAllDay: false)
        let unknown = PollSchedule.Health(usMarketOpen: nil)
        XCTAssertTrue(PollSchedule.regularHoursOpen(unknown, book: book))
        let dead = PollSchedule.Health(usMarketOpen: nil, deadBatches: 3)
        XCTAssertFalse(PollSchedule.regularHoursOpen(dead, book: book))
        XCTAssertEqual(PollSchedule.nextDelay(book: book, health: dead, now: Date()), 30 * 60)
    }

    func testBackoffStartsAtAFullMinute() {
        XCTAssertEqual(PollSchedule.backoff(step: 1), 60)
        XCTAssertEqual(PollSchedule.backoff(step: 4), 300)
        XCTAssertEqual(PollSchedule.backoff(step: 9), 300)
    }
}

final class CreditGovernorTests: XCTestCase {
    /// Deterministic clock and sleep so the minute rollover can be driven by the test.
    final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var t: TimeInterval
        init(_ t: TimeInterval) { self.t = t }
        var now: Date { lock.lock(); defer { lock.unlock() }; return Date(timeIntervalSince1970: t) }
        func advance(_ s: TimeInterval) { lock.lock(); t += s; lock.unlock() }
    }

    func testMinuteBucketAndDailyReserve() async throws {
        let clock = Clock(1_789_740_000) // an exact minute boundary
        let store = MemoryGovernorStore()
        let gov = CreditGovernor(store: store, now: { clock.now }, sleep: { s in clock.advance(s) })

        try await gov.acquire(cost: 4, userInitiated: false)
        try await gov.acquire(cost: 1, userInitiated: false)
        let m1 = await gov.minuteState()
        XCTAssertEqual(m1.used, 5)

        // 5 + 5 > 8: the governor sleeps into the next minute (fake sleep advances the clock)
        try await gov.acquire(cost: 5, userInitiated: true)
        let m2 = await gov.minuteState()
        XCTAssertEqual(m2.used, 5)
        XCTAssertGreaterThan(m2.minuteIndex, m1.minuteIndex)
        let day = await gov.dayState()
        XCTAssertEqual(day.used, 10)

        // Daily reserve: background work stops at 760, user work may continue to 800
        store.saveDay(GovernorDay(utcDate: MarketClock.utcDayString(clock.now), used: 758))
        do {
            try await gov.acquire(cost: 4, userInitiated: false)
            XCTFail("background poll should be refused inside the reserve")
        } catch let e as TapeError {
            XCTAssertEqual(e, .budgetExhausted)
        }
        try await gov.acquire(cost: 1, userInitiated: true)
        let day2 = await gov.dayState()
        XCTAssertEqual(day2.used, 759)
    }

    func testOverLimitRequestFailsImmediately() async {
        // A 9-name batch can never fit an 8-a-minute bucket; it must not wait forever (Kimi C1)
        let gov = CreditGovernor(store: MemoryGovernorStore(), sleep: { _ in XCTFail("must not sleep") })
        do {
            try await gov.acquire(cost: 9, userInitiated: false)
            XCTFail("expected requestTooLarge")
        } catch let e as TapeError {
            XCTAssertEqual(e, .requestTooLarge(cost: 9, limit: 8))
        } catch {
            XCTFail("unexpected \(error)")
        }
        XCTAssertEqual(["A", "B", "C", "D", "E", "F", "G", "H", "I"].chunked(by: 8).map(\.count), [8, 1])
        XCTAssertEqual([String]().chunked(by: 8).count, 0)
    }

    func testWaitReleasesTheGateForOthers() async throws {
        // A background poll waiting for the next minute must not block a user tap that fits now (Kimi M3)
        let clock = Clock(1_789_740_000)
        let gov = CreditGovernor(store: MemoryGovernorStore(), now: { clock.now }, sleep: { s in clock.advance(s) })
        try await gov.acquire(cost: 7, userInitiated: false)
        // 7 + 4 > 8: this one sleeps into the next minute; meanwhile a 1-credit tap should pass at once
        async let big: Void = gov.acquire(cost: 4, userInitiated: false)
        try await gov.acquire(cost: 1, userInitiated: true)
        let m = await gov.minuteState()
        XCTAssertTrue(m.used == 8 || m.used == 4 || m.used == 5, "tap admitted without waiting for the big request, got \(m.used)")
        try await big
    }

    func testRateLimitMarksMinuteFull() async {
        let gov = CreditGovernor(store: MemoryGovernorStore())
        await gov.markMinuteExhausted()
        let m = await gov.minuteState()
        XCTAssertEqual(m.used, 8)
    }
}

final class ClientTests: XCTestCase {
    /// Scripted transport: returns the queued (body, status) pairs in order and records URLs.
    final class FakeTransport: HTTPTransport, @unchecked Sendable {
        private let lock = NSLock()
        var queue: [(String, Int)]
        var urls: [URL] = []
        var headers: [[String: String]] = []
        init(_ queue: [(String, Int)]) { self.queue = queue }
        func get(_ url: URL, headers: [String: String]) async throws -> (Data, Int) {
            lock.lock(); defer { lock.unlock() }
            urls.append(url); self.headers.append(headers)
            guard !queue.isEmpty else { throw URLError(.notConnectedToInternet) }
            let (body, status) = queue.removeFirst()
            return (Data(body.utf8), status)
        }
    }

    func testKeyTravelsOnlyInTheHeader() async throws {
        let t = FakeTransport([("{\"symbol\":\"SPY\",\"close\":\"655.2\"}", 200)])
        let c = TwelveDataClient(apiKey: "SECRET", transport: t)
        _ = try await c.quotes(symbols: ["SPY"])
        XCTAssertEqual(t.headers.first?["Authorization"], "apikey SECRET")
        XCTAssertFalse(t.urls.first!.absoluteString.contains("SECRET"))
        XCTAssertFalse(t.urls.first!.absoluteString.contains("apikey"))
    }

    func testTransportFailureNeverDemotesAuth() async {
        // Offline: the error is a network error and the next call still uses the header (Kimi C2)
        let t = FakeTransport([])
        let c = TwelveDataClient(apiKey: "SECRET", transport: t)
        do { _ = try await c.quotes(symbols: ["SPY"]); XCTFail("expected failure") }
        catch let e as TapeError { if case .network = e {} else { XCTFail("expected network, got \(e)") } }
        catch { XCTFail("unexpected \(error)") }
        XCTAssertEqual(t.urls.count, 1)
        XCTAssertFalse(t.urls[0].absoluteString.contains("apikey"))
    }

    func testHttpStatusIsHonoredBeforeTheBody() async {
        // A Cloudflare-style HTML 429 must reach the rate-limit path, not read as noise (Kimi C5)
        for (status, expectRateLimited, expectUnauthorized) in [(429, true, false), (403, false, true), (401, false, true)] {
            let t = FakeTransport([("<html>blocked</html>", status)])
            let c = TwelveDataClient(apiKey: "k", transport: t)
            do { _ = try await c.quotes(symbols: ["SPY"]); XCTFail("expected failure for \(status)") }
            catch let e as TapeError {
                switch e {
                case .rateLimited: XCTAssertTrue(expectRateLimited, "status \(status)")
                case .unauthorized: XCTAssertTrue(expectUnauthorized, "status \(status)")
                default: XCTFail("status \(status) mapped to \(e)")
                }
            } catch { XCTFail("unexpected \(error)") }
        }
        let five = FakeTransport([("oops", 503)])
        do { _ = try await TwelveDataClient(apiKey: "k", transport: five).quotes(symbols: ["SPY"]); XCTFail() }
        catch let e as TapeError { if case .network = e {} else { XCTFail("503 should be network, got \(e)") } }
        catch { XCTFail() }
    }

    func testBatchWithPartialErrors() async throws {
        let body = """
        {"SPY":{"symbol":"SPY","close":"655.2","is_market_open":true},
         "ZZQ":{"code":400,"message":"**symbol** not found: ZZQ","status":"error"}}
        """
        let c = TwelveDataClient(apiKey: "k", transport: FakeTransport([(body, 200)]))
        let r = try await c.quotes(symbols: ["SPY", "ZZQ", "MISSING"])
        if case .success(let q)? = r["SPY"] { XCTAssertEqual(q.last, 655.2) } else { XCTFail("SPY should decode") }
        if case .failure(let e)? = r["ZZQ"] { XCTAssertEqual(e, .api(code: 400, message: "**symbol** not found: ZZQ")) } else { XCTFail("ZZQ should be an error") }
        if case .failure? = r["MISSING"] {} else { XCTFail("absent symbol should be an error") }
    }

    func testBodyLevelErrorsStillMap() async {
        let c = TwelveDataClient(apiKey: "k", transport: FakeTransport([("{\"code\":401,\"message\":\"bad key\",\"status\":\"error\"}", 200)]))
        do { _ = try await c.validateKey(); XCTFail() }
        catch let e as TapeError { XCTAssertEqual(e, .unauthorized("bad key")) }
        catch { XCTFail() }
    }
}

final class LossyDoubleTests: XCTestCase {
    func testRejectsNonFinite() throws {
        struct Box: Codable { var v: LossyDouble? }
        let nan = try JSONDecoder().decode(Box.self, from: Data("{\"v\":\"NaN\"}".utf8))
        XCTAssertNil(nan.v?.value)
        let inf = try JSONDecoder().decode(Box.self, from: Data("{\"v\":\"inf\"}".utf8))
        XCTAssertNil(inf.v?.value)
        let ok = try JSONDecoder().decode(Box.self, from: Data("{\"v\":\"1,234.5\"}".utf8))
        XCTAssertEqual(ok.v?.value, 1234.5)
    }

    func testConventionDefaults() {
        XCTAssertEqual(UpColorConvention.defaultFor(regionCode: "CN"), .redUp)
        XCTAssertEqual(UpColorConvention.defaultFor(regionCode: "US"), .greenUp)
        XCTAssertEqual(UpColorConvention.defaultFor(regionCode: nil), .greenUp)
        XCTAssertEqual(Direction.glyph(1.2), "▲")
        XCTAssertEqual(Direction.glyph(-0.1), "▼")
        XCTAssertEqual(Direction.glyph(0), "")
    }
}

final class SymbolSearchTests: XCTestCase {
    func testGoldSurfacesEveryKind() {
        let api = SymbolSearch.fromAPI([
            RawSearchHit(symbol: "GOLD", instrumentName: "Barrick Gold Corp", exchange: "NYSE", instrumentType: "Common Stock", currency: "USD"),
            RawSearchHit(symbol: "GOLD", instrumentName: "Visi Telekomunikasi", exchange: "IDX", instrumentType: "Common Stock", currency: "IDR"),
            RawSearchHit(symbol: "GOLDBEES", instrumentName: "Nippon India ETF Gold BeES", exchange: "NSE", instrumentType: "ETF", currency: "INR")
        ], query: "gold")
        XCTAssertEqual(api.map(\.symbol), ["GOLD"]) // foreign listings filtered out
        let ranked = SymbolSearch.rank(local: SymbolSearch.localMatches("gold"), api: api)
        XCTAssertEqual(Array(ranked.prefix(4).map(\.symbol)), ["GOLD", "GLD", "XAU/USD", "PAXG/USD"])
        XCTAssertEqual(Array(ranked.prefix(4).map(\.type)), [.stock, .etf, .commodity, .crypto])
        XCTAssertLessThanOrEqual(ranked.count, SymbolSearch.maxResults)
    }

    func testPairBeatsPrefixForBTC() {
        let api = SymbolSearch.fromAPI([
            RawSearchHit(symbol: "BTC", instrumentName: "Grayscale Bitcoin Mini Trust ETF", exchange: "NYSE", instrumentType: "ETF", currency: "USD"),
            RawSearchHit(symbol: "BTC/USD", instrumentName: "Bitcoin US Dollar", exchange: "Binance", instrumentType: "Digital Currency", currency: ""),
            RawSearchHit(symbol: "BTC/USD", instrumentName: "Bitcoin US Dollar", exchange: "Coinbase Pro", instrumentType: "Digital Currency", currency: "")
        ], query: "btc")
        let ranked = SymbolSearch.rank(local: SymbolSearch.localMatches("btc"), api: api)
        XCTAssertEqual(ranked.first?.symbol, "BTC/USD")
        XCTAssertEqual(ranked.dropFirst().first?.symbol, "BTC")
        XCTAssertEqual(ranked.first?.instrument.session, .allDay)
    }

    func testExclusionAndRaw() {
        let ranked = SymbolSearch.rank(local: SymbolSearch.localMatches("spy"), api: [], excluding: ["SPY"])
        XCTAssertFalse(ranked.contains { $0.symbol == "SPY" })
        XCTAssertEqual(SymbolSearch.rawSymbol(" brk.b "), "BRK.B")
        XCTAssertEqual(SymbolSearch.rawSymbol("btc/usd"), "BTC/USD")
    }
}

final class QuoteDecodingTests: XCTestCase {
    func testDecodesStringNumbers() throws {
        let json = """
        {"symbol":"AAPL","name":"Apple Inc.","exchange":"NASDAQ","datetime":"2026-09-18","timestamp":1789738200,"last_quote_at":1789761540,
         "open":"337.98999","high":"338.48999","low":"332.53000","close":"335.59000","volume":"35660958","previous_close":"337",
         "change":"-1.41","percent_change":"-0.41839","average_volume":"49158440","is_market_open":false,
         "fifty_two_week":{"low":"236.64999","high":"344.57001"},"extended_price":"335.80","extended_percent_change":"0.06"}
        """.data(using: .utf8)!
        let q = try JSONDecoder().decode(Quote.self, from: json)
        XCTAssertEqual(q.last, 335.59)
        XCTAssertEqual(q.prevClose, 337)
        XCTAssertEqual(q.isMarketOpen, false)
        XCTAssertEqual(q.fiftyTwoWeek?.high?.value, 344.57001)
        XCTAssertEqual(q.sessionDate, "2026-09-18")
        XCTAssertEqual(q.extendedPrice?.value, 335.80)
        // round-trips through our own cache encoding
        let again = try JSONDecoder().decode(Quote.self, from: try JSONEncoder().encode(q))
        XCTAssertEqual(again, q)
    }
}
