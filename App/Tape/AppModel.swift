import Foundation
import SwiftUI
import Observation
import TapeCore

/// One observable model for the whole app. All state mutation happens on the main actor;
/// network calls go through the TapeCore actors.
@MainActor
@Observable
final class AppModel {
    // MARK: persisted state
    var apiKey: String = ""
    var symbols: [String] = []
    var meta: [String: Instrument] = [:]
    var quotes: [String: Quote] = [:]
    var quoteErrors: [String: String] = [:]
    /// Consecutive failed batches per symbol. At `PollSchedule.quarantineThreshold` the row is
    /// paused and no longer billed until the user resumes it (Kimi review C3 / U8).
    var failures: [String: Int] = [:]
    var series: [String: PriceSeries] = [:]
    var selected: String? = nil
    var timeframe: Timeframe = .day
    var lastUpdate: Date? = nil
    var usMarketOpen: Bool? = nil
    var upColor: UpColorConvention = .greenUp

    // MARK: transient state
    var hover: Int? = nil
    var limitedStep: Int = 0
    var budgetExhausted = false
    var stale = false
    var deadBatches: Int = 0
    var keyInvalid = false
    var keyMessage: String? = nil
    var keyValidating = false
    var chartMessage: String? = nil
    var toast: String? = nil
    var toastUndo: Bool = false
    var showSettings = false
    var showStatusInfo = false
    var removeArmed: String? = nil
    var highlighted: String? = nil
    var isActive = true
    /// Live price shown on the chart's last point while an instrument trades. Kept apart
    /// from `series` so the cache only ever holds parser output (Kimi review M5).
    var liveOverride: [String: Double] = [:]

    // search
    var searchText: String = ""
    var searchResults: [SearchResult] = []
    var searchLoading = false
    var searchNote: String? = nil

    // MARK: plumbing
    @ObservationIgnored private let store: Store
    @ObservationIgnored private let governor: CreditGovernor
    @ObservationIgnored private var client: TwelveDataClient? = nil
    @ObservationIgnored private var pollTask: Task<Void, Never>? = nil
    @ObservationIgnored private var seriesTask: Task<Void, Never>? = nil
    @ObservationIgnored private var searchTask: Task<Void, Never>? = nil
    @ObservationIgnored private var toastTask: Task<Void, Never>? = nil
    @ObservationIgnored private var removeTask: Task<Void, Never>? = nil
    @ObservationIgnored private var highlightTask: Task<Void, Never>? = nil
    @ObservationIgnored private var quotesInFlight = false
    @ObservationIgnored private var searchCache: [String: SearchCacheEntry] = [:]
    @ObservationIgnored private var booted = false
    @ObservationIgnored private var lastRemoved: (symbol: String, index: Int, instrument: Instrument?)? = nil

    private struct SearchCacheEntry: Codable { var at: Date; var items: [SearchResult] }
    private struct QuoteCache: Codable { var at: Date; var open: Bool?; var quotes: [String: Quote]; var errors: [String: String]? }

    enum Reason { case boot, timer, wake, user }

    init(store: Store = Store()) {
        self.store = store
        self.governor = CreditGovernor(store: DefaultsGovernorStore(store: store))
    }

    // MARK: derived

    var activeSymbols: [String] { symbols.filter { !isQuarantined($0) } }
    func isQuarantined(_ symbol: String) -> Bool { (failures[symbol] ?? 0) >= PollSchedule.quarantineThreshold }

    var book: PollSchedule.Book {
        let active = activeSymbols
        return PollSchedule.Book(symbols: active.count,
                                 hasRegularHours: active.contains { instrument(for: $0).session == .regularHours },
                                 hasAllDay: active.contains { instrument(for: $0).session == .allDay })
    }

    var health: PollSchedule.Health {
        PollSchedule.Health(usMarketOpen: usMarketOpen, limitedBackoffStep: limitedStep, budgetExhausted: budgetExhausted,
                            deadBatches: deadBatches, keyInvalid: keyInvalid)
    }

    func instrument(for symbol: String) -> Instrument {
        meta[symbol] ?? Instrument.inferred(symbol: symbol)
    }

    func series(for symbol: String, _ tf: Timeframe) -> PriceSeries? { series[seriesKey(symbol, tf)] }

    /// The cached series with the live price on its last point while the instrument trades.
    func displaySeries(for symbol: String, _ tf: Timeframe) -> PriceSeries? {
        guard var s = series(for: symbol, tf), !s.points.isEmpty else { return series(for: symbol, tf) }
        guard let live = liveOverride[symbol] else { return s }
        if instrument(for: symbol).session == .regularHours, tf == .day, let qd = quotes[symbol]?.sessionDate, let sd = s.sessionDate, qd != sd { return s }
        s.points[s.points.count - 1].value = live
        return s
    }

    private func seriesKey(_ symbol: String, _ tf: Timeframe) -> String { symbol + "|" + tf.rawValue }

    enum Status: String { case noKey = "NO KEY", keyInvalid = "KEY REJECTED", ready = "READY", connecting = "CONNECTING", open = "OPEN", closed = "CLOSED", usClosed = "US CLOSED", limited = "LIMITED", stale = "STALE", dead = "NOT RESOLVING" }

    var status: Status {
        if apiKey.isEmpty { return .noKey }
        if keyInvalid { return .keyInvalid }
        if limitedStep > 0 || budgetExhausted { return .limited }
        if !symbols.isEmpty && deadBatches >= PollSchedule.deadBookThreshold { return .dead }
        if stale || PollSchedule.feedIsStale(lastUpdate: lastUpdate, newestQuoteAt: newestOpenQuoteAt, book: book, health: health, now: Date()) { return .stale }
        if usMarketOpen == true { return .open }
        if usMarketOpen == false { return book.hasAllDay ? .usClosed : .closed }
        if !book.hasRegularHours && book.hasAllDay && lastUpdate != nil { return .open }
        if symbols.isEmpty { return .ready }
        return .connecting
    }

    /// Plain-language explanation for the status chip (Kimi review U5).
    var statusExplanation: (title: String, detail: String) {
        switch status {
        case .noKey: return ("No data key yet", "Add a free Twelve Data key in Settings to load live prices. Everything else works without one.")
        case .keyInvalid: return ("Twelve Data rejected the key", "Check for typos or generate a new key at twelvedata.com. Polling is paused until a key is accepted.")
        case .ready: return ("Ready", "Search above to add a stock, ETF, commodity or crypto pair.")
        case .connecting: return ("Connecting", "Waiting for the first quote batch from Twelve Data.")
        case .open: return ("US market open", "Quotes refresh every \(Int(PollSchedule.interval(symbols: book.symbols, hasAllDay: book.hasAllDay, night: false) / 60)) minutes on the free plan. Pull down to refresh sooner; that draws on the daily reserve.")
        case .closed: return ("US market closed", "Prices are frozen at the close. " + reopenLine())
        case .usClosed: return ("US market closed", "US rows are frozen at the close; the 24-hour rows keep refreshing every \(Int(PollSchedule.interval(symbols: book.symbols, hasAllDay: true, night: true) / 60)) minutes. " + reopenLine())
        case .limited: return budgetExhausted ? ("Daily free-plan budget used", "Background refresh pauses until 00:00 UTC (20:00 New York). Your own taps still work while a small reserve lasts.")
                                              : ("Twelve Data is rate limiting", "The free plan allows 8 calls a minute. Backing off and retrying automatically.")
        case .stale: return ("Prices may be stale", "The last refresh failed or the feed has gone quiet. Check the connection, or pull down to try again.")
        case .dead: return ("Nothing on the tape is resolving", "Every symbol failed on the last three refreshes. Remove or retype them; each failed lookup still costs a credit.")
        }
    }

    private func reopenLine() -> String {
        let next = MarketClock.newYork.nextOpen(after: Date())
        return "Next session \(next.sameDay ? "today" : next.weekday) 09:30 ET (in \(Format.duration(next.interval))), holidays aside."
    }

    private var newestOpenQuoteAt: Date? {
        var newest: Double = 0
        for s in activeSymbols {
            guard let q = quotes[s], instrument(for: s).session == .regularHours, q.isMarketOpen == true, let t = q.lastQuoteAt else { continue }
            newest = max(newest, t)
        }
        return newest > 0 ? Date(timeIntervalSince1970: newest) : nil
    }

    var footerText: String {
        guard !symbols.isEmpty else { return "Data by Twelve Data." }
        var parts: [String] = []
        let n = max(1, book.symbols)
        let rthMin = Int(PollSchedule.interval(symbols: n, hasAllDay: book.hasAllDay, night: false) / 60)
        let nightMin = Int(PollSchedule.interval(symbols: n, hasAllDay: true, night: true) / 60)
        if book.hasAllDay && book.hasRegularHours {
            parts.append("Quotes refresh every \(rthMin) minutes while US markets are open and every \(nightMin) minutes overnight for the 24-hour rows.")
        } else if book.hasAllDay {
            parts.append("Quotes refresh every \(nightMin) minutes around the clock.")
        } else {
            parts.append("Quotes refresh every \(rthMin) minutes while the market is open and sleep until the next session when it is closed.")
        }
        if usMarketOpen == false && book.hasRegularHours { parts.append(reopenLine()) }
        parts.append("Data by Twelve Data.")
        return parts.joined(separator: " ")
    }

    var creditsUsedToday: Int { store.load(.creditsDay, as: GovernorDay.self).flatMap { $0.utcDate == MarketClock.utcDayString(Date()) ? $0.used : nil } ?? 0 }

    // MARK: boot & lifecycle

    func boot() {
        guard !booted else { return }
        booted = true
        apiKey = KeychainStore.read() ?? ""
        symbols = store.load(.symbols, as: [String].self) ?? []
        meta = store.load(.meta, as: [String: Instrument].self) ?? [:]
        failures = store.load(.failures, as: [String: Int].self) ?? [:]
        selected = store.load(.selected, as: String.self).flatMap { symbols.contains($0) ? $0 : nil } ?? symbols.first
        timeframe = store.load(.timeframe, as: Timeframe.self) ?? .day
        upColor = store.load(.upColor, as: UpColorConvention.self) ?? UpColorConvention.defaultFor(regionCode: Locale.current.region?.identifier)
        searchCache = store.load(.searchCache, as: [String: SearchCacheEntry].self) ?? [:]
        if let cache = store.load(.quotes, as: QuoteCache.self) {
            quotes = cache.quotes
            quoteErrors = cache.errors ?? [:]
            lastUpdate = cache.at
            usMarketOpen = cache.open
        }
        series = store.load(.series, as: [String: PriceSeries].self) ?? [:]
        if !apiKey.isEmpty {
            makeClient()
            refreshIfNeeded(reason: .boot)
            if let s = selected { loadSeries(symbol: s, timeframe: timeframe, userInitiated: false) }
        } else {
            showSettings = true
        }
    }

    private func makeClient() {
        client = TwelveDataClient(apiKey: apiKey)
    }

    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .active:
            isActive = true
            refreshIfNeeded(reason: .wake)
        case .background, .inactive:
            isActive = false
            pollTask?.cancel(); pollTask = nil
        @unknown default:
            break
        }
    }

    // MARK: key (Kimi review U2 / M1)

    /// Validates the key with one credit before it is accepted. On a rejection the sheet stays
    /// open with the vendor's message; offline, the key is saved and verified on the next batch.
    func saveKey(_ raw: String) {
        let k = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { keyMessage = "Paste a key first."; return }
        guard !keyValidating else { return }
        keyValidating = true
        keyMessage = nil
        let probe = TwelveDataClient(apiKey: k)
        let gov = governor
        Task { @MainActor [weak self] in
            defer { self?.keyValidating = false }
            do {
                _ = try await gov.run(cost: 1, userInitiated: true) { try await probe.validateKey() }
                self?.acceptKey(k, verified: true)
            } catch let e as TapeError {
                switch e {
                case .unauthorized(let m):
                    self?.keyMessage = "Twelve Data rejected this key: \(m)"
                case .rateLimited:
                    self?.keyMessage = "Rate limited right now; try again in a minute."
                case .budgetExhausted:
                    self?.acceptKey(k, verified: false)
                    self?.showToast("Key saved. Daily budget is used up, so it will be verified on the next refresh.")
                default:
                    self?.acceptKey(k, verified: false)
                    self?.showToast("Key saved but not verified yet: \(e.message)")
                }
            } catch {
                self?.acceptKey(k, verified: false)
                self?.showToast("Key saved but not verified yet.")
            }
        }
    }

    private func acceptKey(_ k: String, verified: Bool) {
        apiKey = k
        KeychainStore.write(k)
        keyInvalid = false
        keyMessage = nil
        limitedStep = 0; budgetExhausted = false; stale = false; deadBatches = 0
        makeClient()
        showSettings = false
        if verified { showToast("Connected to Twelve Data.") }
        if !symbols.isEmpty { loadQuotes(reason: .user) }
        if let s = selected { loadSeries(symbol: s, timeframe: timeframe, userInitiated: true) }
    }

    func clearKey() {
        apiKey = ""
        KeychainStore.delete()
        client = nil
        keyInvalid = false
        keyMessage = nil
        pollTask?.cancel(); pollTask = nil
        showToast("Key removed from this device.")
    }

    // MARK: quotes

    private func refreshIfNeeded(reason: Reason) {
        guard !apiKey.isEmpty, !keyInvalid, !activeSymbols.isEmpty, isActive else { return }
        if PollSchedule.refreshNeeded(lastUpdate: lastUpdate, book: book, health: health, now: Date()) {
            loadQuotes(reason: reason)
        } else {
            schedulePolling()
        }
    }

    /// Pull-to-refresh and other explicit taps. Draws on the daily reserve (Kimi review U4).
    func refresh() async {
        guard !apiKey.isEmpty, !keyInvalid, !activeSymbols.isEmpty else { return }
        pollTask?.cancel()
        loadQuotes(reason: .user)
        try? await Task.sleep(nanoseconds: 700_000_000)
    }

    func loadQuotes(reason: Reason) {
        guard let client, !keyInvalid, isActive, !quotesInFlight else { return }
        let syms = activeSymbols
        guard !syms.isEmpty else { return }
        quotesInFlight = true
        let userInitiated = reason == .user
        let gov = governor
        let chunks = syms.chunked(by: PollSchedule.maxBatch)
        Task { @MainActor [weak self] in
            defer { self?.quotesInFlight = false; self?.schedulePolling() }
            var merged: [String: Result<Quote, TapeError>] = [:]
            var failure: TapeError? = nil
            for chunk in chunks {
                do {
                    let part = try await gov.run(cost: chunk.count, userInitiated: userInitiated) { try await client.quotes(symbols: chunk) }
                    for (k, v) in part { merged[k] = v }
                } catch let e as TapeError {
                    failure = e
                    break
                } catch {
                    failure = .network(error.localizedDescription)
                    break
                }
            }
            guard let self else { return }
            if !merged.isEmpty { self.absorb(merged, requested: syms) }
            if let e = failure { self.handle(e, context: "quotes") }
        }
    }

    /// Folds a batch into state: per-symbol success/failure counts, dead-book latch, market
    /// state latched only from batches that carried at least one live equity quote (Kimi C3).
    private func absorb(_ result: [String: Result<Quote, TapeError>], requested: [String]) {
        var anyOpen: Bool? = nil
        var successes = 0
        var newlyQuarantined: [String] = []
        for s in requested {
            switch result[s] {
            case .success(let q)?:
                successes += 1
                quotes[s] = q
                quoteErrors[s] = nil
                failures[s] = 0
                if instrument(for: s).session == .regularHours, let open = q.isMarketOpen { anyOpen = (anyOpen ?? false) || open }
                if meta[s] == nil || meta[s]?.name.isEmpty == true, let name = q.name, !name.isEmpty {
                    var inst = instrument(for: s); inst.name = name; meta[s] = inst
                }
                if instrument(for: s).session == .allDay || q.isMarketOpen == true, let live = q.last { liveOverride[s] = live } else { liveOverride[s] = nil }
            case .failure(let e)?:
                quoteErrors[s] = e.message
                let n = (failures[s] ?? 0) + 1
                failures[s] = n
                if n == PollSchedule.quarantineThreshold { newlyQuarantined.append(s) }
            case nil:
                break
            }
        }
        if successes == 0 { deadBatches += 1 } else { deadBatches = 0 }
        if let open = anyOpen { usMarketOpen = open }
        else if !book.hasRegularHours { usMarketOpen = nil }
        lastUpdate = Date()
        limitedStep = 0; budgetExhausted = false; stale = false
        store.save(meta, for: .meta)
        store.save(failures, for: .failures)
        store.save(QuoteCache(at: lastUpdate!, open: usMarketOpen, quotes: quotes, errors: quoteErrors), for: .quotes)
        if !newlyQuarantined.isEmpty {
            showToast("\(newlyQuarantined.joined(separator: ", ")) paused after \(PollSchedule.quarantineThreshold) failed lookups. Tap the row to retry.")
        } else if let first = requested.first(where: { failures[$0] == 1 }) {
            showToast("\(first) isn't resolving. It costs a credit on every refresh until it is fixed or removed.")
        }
        if selected == nil, let first = symbols.first { select(first, userInitiated: false) }
    }

    private func schedulePolling() {
        pollTask?.cancel()
        guard isActive, !apiKey.isEmpty, !keyInvalid else { return }
        guard let delay = PollSchedule.nextDelay(book: book, health: health, now: Date(), jitter: Double.random(in: -0.2...0.2)) else { return }
        pollTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.loadQuotes(reason: .timer)
        }
    }

    private func handle(_ e: TapeError, context: String) {
        switch e {
        case .unauthorized(let m):
            keyInvalid = true
            keyMessage = "Twelve Data rejected this key: \(m)"
            pollTask?.cancel(); pollTask = nil
            if !showSettings { showSettings = true }
        case .rateLimited:
            limitedStep = min(limitedStep + 1, 4)
            let gov = governor
            Task { await gov.markMinuteExhausted() }
            showToast("Rate limit hit (8 calls a minute on the free plan). Backing off.")
        case .budgetExhausted:
            budgetExhausted = true
            showToast(context == "quotes" ? "Daily credit budget reached. Background refresh paused until 00:00 UTC." : "Daily credit budget nearly used up; keeping a reserve for your own actions.")
        case .requestTooLarge:
            showToast("Too many names for one refresh; the list is capped at \(PollSchedule.maxSymbols).")
        case .cancelled:
            break
        case .network, .decoding, .api:
            if context == "quotes" && lastUpdate != nil { stale = true }
            if context != "search" { showToast(lastUpdate != nil ? "Could not refresh prices; showing the last good numbers." : e.message) }
        }
    }

    // MARK: series

    func loadSeries(symbol: String, timeframe tf: Timeframe, userInitiated: Bool, force: Bool = false) {
        guard let client, !keyInvalid else { return }
        let key = seriesKey(symbol, tf)
        let inst = instrument(for: symbol)
        let spec = TimeframeSpec.spec(for: tf, session: inst.session)
        if !force, let cached = series[key], Date().timeIntervalSince(cached.fetchedAt) < spec.cacheSeconds {
            if selected == symbol && timeframe == tf { chartMessage = nil }
            return
        }
        seriesTask?.cancel()
        chartMessage = series[key] == nil ? "Loading…" : nil
        let gov = governor
        seriesTask = Task { @MainActor [weak self] in
            do {
                let bars = try await gov.run(cost: 1, userInitiated: userInitiated) { try await client.timeSeries(symbol: symbol, spec: spec) }
                guard !Task.isCancelled, let self else { return }
                guard let parsed = SeriesParser.parse(bars: bars, timeframe: tf, session: inst.session) else {
                    if self.selected == symbol && self.timeframe == tf { self.chartMessage = "No chart data for \(symbol)" }
                    return
                }
                self.series[key] = parsed
                self.pruneAndPersistSeries()
                if self.selected == symbol && self.timeframe == tf { self.chartMessage = nil }
            } catch let e as TapeError {
                guard let self, e != .cancelled else { return }
                if self.selected == symbol && self.timeframe == tf && self.series[key] == nil {
                    switch e {
                    case .rateLimited: self.chartMessage = "Rate limit hit. Try again in a minute."
                    case .budgetExhausted: self.chartMessage = "Daily credit budget reached."
                    default: self.chartMessage = e.message
                    }
                }
                self.handle(e, context: "series")
            } catch {
                self?.chartMessage = "Chart unavailable"
            }
        }
    }

    /// "Try again" on a failed chart (Kimi review U10). Costs one credit.
    func retryChart() {
        guard let s = selected else { return }
        loadSeries(symbol: s, timeframe: timeframe, userInitiated: true, force: true)
    }

    private func pruneAndPersistSeries() {
        let keep = series.sorted { $0.value.fetchedAt > $1.value.fetchedAt }.prefix(24)
        series = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        store.save(series, for: .series)
    }

    // MARK: selection & timeframe

    func select(_ symbol: String, userInitiated: Bool) {
        selected = symbol
        hover = nil
        chartMessage = nil
        disarmRemove()
        store.save(symbol, for: .selected)
        if !apiKey.isEmpty { loadSeries(symbol: symbol, timeframe: timeframe, userInitiated: userInitiated) }
    }

    func setTimeframe(_ tf: Timeframe) {
        timeframe = tf
        hover = nil
        chartMessage = nil
        store.save(tf, for: .timeframe)
        if let s = selected, !apiKey.isEmpty { loadSeries(symbol: s, timeframe: tf, userInitiated: true) }
    }

    func setUpColor(_ c: UpColorConvention) {
        upColor = c
        store.save(c, for: .upColor)
    }

    /// Reference price for the change readout: previous close for a regular-hours day,
    /// otherwise the first point of the visible series. Keyed by symbol, not by the current
    /// selection, so a row and a detail page for different names never disagree (Kimi M7).
    func referenceValue(for symbol: String, timeframe tf: Timeframe? = nil) -> Double? {
        let timeframe = tf ?? self.timeframe
        let q = quotes[symbol]
        let s = series(for: symbol, timeframe)
        if instrument(for: symbol).session == .allDay {
            return s?.first ?? q?.prevClose
        }
        if timeframe == .day {
            if let q, let s, let sd = s.sessionDate, q.sessionDate == sd { return q.prevClose }
            if let q, s == nil { return q.prevClose }
            return s?.first ?? q?.prevClose
        }
        return s?.first
    }

    func sessionLabel(for symbol: String) -> String {
        let inst = instrument(for: symbol)
        let spec = TimeframeSpec.spec(for: timeframe, session: inst.session)
        if inst.session == .allDay || timeframe != .day { return spec.label }
        if let sd = series(for: symbol, .day)?.sessionDate, sd != MarketClock.newYork.dayString(Date()) {
            return Format.weekday(sd) + " " + Format.shortDate(sd)
        }
        return "Today"
    }

    func sessionComplete(for symbol: String) -> Bool {
        if usMarketOpen == false { return true }
        if let sd = series(for: symbol, .day)?.sessionDate, sd != MarketClock.newYork.dayString(Date()) { return true }
        return false
    }

    // MARK: list edits

    func add(_ result: SearchResult) {
        add(symbol: result.symbol, instrument: result.instrument)
    }

    func addRaw(_ text: String) {
        let sym = SymbolSearch.rawSymbol(text)
        guard !sym.isEmpty else { return }
        add(symbol: sym, instrument: nil)
    }

    private func add(symbol: String, instrument inst: Instrument?) {
        searchText = ""; searchResults = []; searchTask?.cancel()
        if symbols.contains(symbol) { flash(symbol); showToast("\(symbol) is already on the tape."); return }
        guard symbols.count < PollSchedule.maxSymbols else {
            showToast("The free plan budget covers up to \(PollSchedule.maxSymbols) names. Remove one to add another.")
            return
        }
        if let inst { meta[symbol] = inst; store.save(meta, for: .meta) }
        failures[symbol] = 0
        symbols.append(symbol)
        store.save(symbols, for: .symbols)
        store.save(failures, for: .failures)
        if selected == nil { select(symbol, userInitiated: true) }
        if apiKey.isEmpty { showSettings = true } else { pollTask?.cancel(); loadQuotes(reason: .user) }
    }

    private func flash(_ symbol: String) {
        highlighted = symbol
        highlightTask?.cancel()
        highlightTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if !Task.isCancelled { self?.highlighted = nil }
        }
    }

    /// Two-tap remove from the detail toolbar: first tap arms for 4 seconds.
    func armOrRemove(_ symbol: String) {
        if removeArmed != symbol {
            removeArmed = symbol
            removeTask?.cancel()
            removeTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if !Task.isCancelled { self?.removeArmed = nil }
            }
            return
        }
        disarmRemove()
        remove(symbol)
    }

    /// Direct removal (swipe). Undo is offered on the toast (Kimi review U7).
    func remove(_ symbol: String) {
        guard let idx = symbols.firstIndex(of: symbol) else { return }
        lastRemoved = (symbol, idx, meta[symbol])
        symbols.remove(at: idx)
        quotes[symbol] = nil
        quoteErrors[symbol] = nil
        failures[symbol] = nil
        liveOverride[symbol] = nil
        store.save(symbols, for: .symbols)
        store.save(failures, for: .failures)
        store.save(QuoteCache(at: lastUpdate ?? Date(), open: usMarketOpen, quotes: quotes, errors: quoteErrors), for: .quotes)
        if selected == symbol {
            selected = nil
            store.remove(.selected)
            if let first = symbols.first { select(first, userInitiated: true) }
        }
        showToast("\(symbol) removed.", undo: true)
    }

    func undoRemove() {
        guard let r = lastRemoved else { return }
        lastRemoved = nil
        guard !symbols.contains(r.symbol) else { return }
        symbols.insert(r.symbol, at: min(r.index, symbols.count))
        if let inst = r.instrument { meta[r.symbol] = inst; store.save(meta, for: .meta) }
        store.save(symbols, for: .symbols)
        toast = nil; toastUndo = false
        if !apiKey.isEmpty { pollTask?.cancel(); loadQuotes(reason: .user) }
    }

    /// Resume a quarantined symbol: one more chance, billed again (Kimi review U8).
    func resume(_ symbol: String) {
        failures[symbol] = 0
        quoteErrors[symbol] = nil
        store.save(failures, for: .failures)
        if !apiKey.isEmpty { pollTask?.cancel(); loadQuotes(reason: .user) }
    }

    func disarmRemove() { removeTask?.cancel(); removeArmed = nil }

    // MARK: search

    func updateSearch(_ text: String) {
        searchText = text
        searchTask?.cancel()
        searchNote = nil
        let q = SymbolSearch.normalize(text)
        guard !q.isEmpty else { searchResults = []; searchLoading = false; return }
        let cached = searchCache[q].flatMap { Date().timeIntervalSince($0.at) < 24 * 3600 ? $0.items : nil }
        searchResults = SymbolSearch.rank(local: SymbolSearch.localMatches(q), api: cached ?? [], excluding: Set(symbols))
        guard cached == nil, q.count >= 2, let client, !keyInvalid else { searchLoading = false; return }
        searchLoading = true
        let gov = governor
        searchTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self else { return }
            do {
                let hits = try await gov.run(cost: 1, userInitiated: true) { try await client.symbolSearch(query: q) }
                guard !Task.isCancelled else { return }
                let items = SymbolSearch.fromAPI(hits, query: q)
                self.searchCache[q] = SearchCacheEntry(at: Date(), items: items)
                let trimmed = self.searchCache.sorted { $0.value.at > $1.value.at }.prefix(50)
                self.searchCache = Dictionary(uniqueKeysWithValues: trimmed.map { ($0.key, $0.value) })
                self.store.save(self.searchCache, for: .searchCache)
                if SymbolSearch.normalize(self.searchText) == q {
                    self.searchResults = SymbolSearch.rank(local: SymbolSearch.localMatches(q), api: items, excluding: Set(self.symbols))
                }
                self.searchLoading = false
            } catch let e as TapeError {
                guard e != .cancelled else { return }
                self.searchLoading = false
                switch e {
                case .rateLimited: self.searchNote = "Rate limit; showing built-in matches"
                case .budgetExhausted: self.searchNote = "Daily budget used; built-in matches only"
                default: self.searchNote = "Search unavailable; built-in matches only"
                }
                self.handle(e, context: "search")
            } catch {
                self.searchLoading = false
            }
        }
    }

    // MARK: toast

    func showToast(_ message: String, undo: Bool = false) {
        toast = message
        toastUndo = undo
        toastTask?.cancel()
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: undo ? 6_000_000_000 : 3_500_000_000)
            if !Task.isCancelled { self?.toast = nil; self?.toastUndo = false }
        }
    }
}
