import Foundation

// MARK: - Instruments

public enum InstrumentType: String, Codable, CaseIterable, Sendable {
    case stock = "Stock"
    case etf = "ETF"
    case commodity = "Commodity"
    case crypto = "Crypto"
    case index = "Index"
    case forex = "Forex"
    case fund = "Fund"
    case other = "Other"

    /// Display order used when the search results are diversified by kind.
    public static let displayOrder: [InstrumentType] = [.stock, .etf, .commodity, .crypto, .index, .forex, .fund, .other]

    /// Maps Twelve Data's `instrument_type` / `exchange` pair onto Tape's kinds.
    public static func from(twelveDataType raw: String, exchange: String) -> InstrumentType {
        if exchange == "COMMODITY" || raw.contains("Metal") || raw.contains("Commodit") || raw.contains("Agricultural") { return .commodity }
        if raw == "Digital Currency" { return .crypto }
        if raw == "Physical Currency" { return .forex }
        if raw == "ETF" { return .etf }
        if raw == "Index" { return .index }
        if raw.contains("Fund") { return .fund }
        if raw.contains("Stock") || raw.contains("Depositary") || raw.contains("REIT") { return .stock }
        return .other
    }
}

/// Which trading clock an instrument follows. US equities and ETFs trade 09:30 to 16:00
/// New York time; crypto, spot metals and forex trade around the clock.
public enum SessionProfile: String, Codable, Sendable {
    case regularHours = "rth"
    case allDay = "24h"

    public static func infer(type: InstrumentType, symbol: String) -> SessionProfile {
        if type == .crypto || type == .commodity || type == .forex || symbol.contains("/") { return .allDay }
        return .regularHours
    }
}

public struct Instrument: Codable, Hashable, Sendable {
    public var symbol: String
    public var name: String
    public var type: InstrumentType
    public var session: SessionProfile

    public init(symbol: String, name: String, type: InstrumentType, session: SessionProfile? = nil) {
        self.symbol = symbol
        self.name = name
        self.type = type
        self.session = session ?? SessionProfile.infer(type: type, symbol: symbol)
    }

    /// Best guess for a symbol typed by hand, before any quote has come back.
    public static func inferred(symbol: String) -> Instrument {
        if let curated = Curated.entry(for: symbol) { return curated }
        let type: InstrumentType = symbol.contains("/") ? .other : .stock
        return Instrument(symbol: symbol, name: "", type: type)
    }
}

// MARK: - Timeframes

public enum Timeframe: String, Codable, CaseIterable, Sendable, Identifiable {
    case day = "1D"
    case week = "1W"
    case month = "1M"
    public var id: String { rawValue }
}

public struct TimeframeSpec: Sendable, Equatable {
    public let interval: String
    public let outputSize: Int
    public let cacheSeconds: TimeInterval
    public let label: String

    public static func spec(for timeframe: Timeframe, session: SessionProfile) -> TimeframeSpec {
        switch (session, timeframe) {
        case (.regularHours, .day):   return TimeframeSpec(interval: "5min",  outputSize: 78, cacheSeconds: 5 * 60,  label: "Today")
        case (.regularHours, .week):  return TimeframeSpec(interval: "30min", outputSize: 65, cacheSeconds: 15 * 60, label: "Past week")
        case (.regularHours, .month): return TimeframeSpec(interval: "1day",  outputSize: 22, cacheSeconds: 60 * 60, label: "Past month")
        case (.allDay, .day):         return TimeframeSpec(interval: "15min", outputSize: 96, cacheSeconds: 5 * 60,  label: "Past 24h")
        case (.allDay, .week):        return TimeframeSpec(interval: "2h",    outputSize: 84, cacheSeconds: 15 * 60, label: "Past week")
        case (.allDay, .month):       return TimeframeSpec(interval: "1day",  outputSize: 30, cacheSeconds: 60 * 60, label: "Past month")
        }
    }

    /// Intraday intervals accept a timezone parameter; daily bars are always exchange-local.
    public var wantsTimezone: Bool { interval != "1day" }
}

// MARK: - Twelve Data payloads

/// Twelve Data sends most numbers as strings ("337.00"). This wrapper decodes either form.
public struct LossyDouble: Codable, Hashable, Sendable {
    public var value: Double?
    public init(_ value: Double?) { self.value = value }
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        var v: Double? = nil
        if c.decodeNil() { v = nil }
        else if let d = try? c.decode(Double.self) { v = d }
        else if let s = try? c.decode(String.self) { v = Double(s.replacingOccurrences(of: ",", with: "")) }
        // "NaN" and "inf" parse as valid Doubles; they would poison chart ranges (Kimi review M4).
        value = (v?.isFinite == true) ? v : nil
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        if let v = value { try c.encode(v) } else { try c.encodeNil() }
    }
}

public struct FiftyTwoWeek: Codable, Hashable, Sendable {
    public var low: LossyDouble?
    public var high: LossyDouble?
}

public struct Quote: Codable, Hashable, Sendable {
    public var symbol: String
    public var name: String?
    public var exchange: String?
    public var currency: String?
    public var datetime: String?
    public var timestamp: Double?
    public var lastQuoteAt: Double?
    public var open: LossyDouble?
    public var high: LossyDouble?
    public var low: LossyDouble?
    public var close: LossyDouble?
    public var volume: LossyDouble?
    public var previousClose: LossyDouble?
    public var change: LossyDouble?
    public var percentChange: LossyDouble?
    public var averageVolume: LossyDouble?
    public var isMarketOpen: Bool?
    public var fiftyTwoWeek: FiftyTwoWeek?
    public var extendedPrice: LossyDouble?
    public var extendedPercentChange: LossyDouble?

    enum CodingKeys: String, CodingKey {
        case symbol, name, exchange, currency, datetime, timestamp
        case lastQuoteAt = "last_quote_at"
        case open, high, low, close, volume
        case previousClose = "previous_close"
        case change
        case percentChange = "percent_change"
        case averageVolume = "average_volume"
        case isMarketOpen = "is_market_open"
        case fiftyTwoWeek = "fifty_two_week"
        case extendedPrice = "extended_price"
        case extendedPercentChange = "extended_percent_change"
    }

    public var last: Double? { close?.value }
    public var dayLow: Double? { low?.value }
    public var dayHigh: Double? { high?.value }
    public var prevClose: Double? { previousClose?.value }
    public var changeValue: Double? { change?.value }
    public var percentChangeValue: Double? { percentChange?.value }
    /// Date part of `datetime` ("2026-09-17").
    public var sessionDate: String? { datetime.map { String($0.prefix(10)) } }
}

public struct Bar: Codable, Hashable, Sendable {
    public var datetime: String
    public var open: LossyDouble?
    public var high: LossyDouble?
    public var low: LossyDouble?
    public var close: LossyDouble?
    public var volume: LossyDouble?

    public init(datetime: String, close: Double?) {
        self.datetime = datetime
        self.close = LossyDouble(close)
    }
}

public struct RawSearchHit: Codable, Hashable, Sendable {
    public var symbol: String
    public var instrumentName: String?
    public var exchange: String?
    public var instrumentType: String?
    public var country: String?
    public var currency: String?

    enum CodingKeys: String, CodingKey {
        case symbol
        case instrumentName = "instrument_name"
        case exchange
        case instrumentType = "instrument_type"
        case country, currency
    }

    public init(symbol: String, instrumentName: String?, exchange: String?, instrumentType: String?, country: String? = nil, currency: String?) {
        self.symbol = symbol
        self.instrumentName = instrumentName
        self.exchange = exchange
        self.instrumentType = instrumentType
        self.country = country
        self.currency = currency
    }
}

// MARK: - Derived series

public struct SeriesPoint: Codable, Hashable, Sendable, Identifiable {
    public var slot: Double
    public var value: Double
    public var label: String
    public var id: Double { slot }
    public init(slot: Double, value: Double, label: String) {
        self.slot = slot; self.value = value; self.label = label
    }
}

public struct AxisLabel: Codable, Hashable, Sendable {
    public var slot: Double
    public var text: String
    public init(slot: Double, text: String) { self.slot = slot; self.text = text }
}

public struct PriceSeries: Codable, Hashable, Sendable {
    public var profile: SessionProfile
    public var timeframe: Timeframe
    public var points: [SeriesPoint]
    /// Width of the x axis in slots. Points sit at `slot / slots` of the width.
    public var slots: Double
    public var days: [String]
    /// For regular-hours 1D: the calendar date of the session the bars belong to.
    public var sessionDate: String?
    public var lastSlot: Double
    /// Precomputed axis labels (24-hour instruments). Regular-hours axes are derived at render time.
    public var axis: [AxisLabel]?
    public var fetchedAt: Date

    public var first: Double? { points.first?.value }
    public var last: Double? { points.last?.value }
    public var low: Double? { points.map(\.value).min() }
    public var high: Double? { points.map(\.value).max() }
}

// MARK: - Search results

public struct SearchResult: Codable, Hashable, Sendable, Identifiable {
    public var symbol: String
    public var name: String
    public var type: InstrumentType
    public var exchange: String?
    public var score: Int
    public var popularity: Int
    public var fromAPI: Bool
    public var id: String { symbol }

    public init(symbol: String, name: String, type: InstrumentType, exchange: String? = nil, score: Int, popularity: Int, fromAPI: Bool) {
        self.symbol = symbol; self.name = name; self.type = type; self.exchange = exchange
        self.score = score; self.popularity = popularity; self.fromAPI = fromAPI
    }

    public var instrument: Instrument { Instrument(symbol: symbol, name: name, type: type) }

    /// A curated entry as a search result, for starter chips and direct adds.
    public static func curated(_ symbol: String) -> SearchResult? {
        guard let inst = Curated.entry(for: symbol) else { return nil }
        return SearchResult(symbol: inst.symbol, name: inst.name, type: inst.type, exchange: nil, score: 100, popularity: 0, fromAPI: false)
    }
}

// MARK: - Errors

public enum TapeError: Error, Equatable, Sendable {
    case unauthorized(String)
    case rateLimited(String)
    case budgetExhausted
    case api(code: Int, message: String)
    case network(String)
    case decoding
    case cancelled
    /// A single request that could never fit the per-minute limit (Kimi review C1).
    case requestTooLarge(cost: Int, limit: Int)

    public var message: String {
        switch self {
        case .unauthorized(let m): return m
        case .rateLimited: return "Rate limit hit (8 calls a minute on the free plan)."
        case .budgetExhausted: return "Daily credit budget reached."
        case .api(_, let m): return m
        case .network(let m): return m
        case .decoding: return "Unexpected response from the data service."
        case .cancelled: return "Cancelled"
        case .requestTooLarge(let cost, let limit): return "A batch of \(cost) cannot fit the \(limit)-a-minute limit."
        }
    }
}

// MARK: - Display conventions

/// Which colour means "up". US and Europe read green as up; mainland China, Hong Kong, Taiwan,
/// Japan and Korea read red as up (红涨绿跌). Colour is never the only channel: every change
/// also carries a sign and a ▲/▼ glyph (Kimi review U3).
public enum UpColorConvention: String, Codable, CaseIterable, Sendable, Identifiable {
    case greenUp = "green-up"
    case redUp = "red-up"
    public var id: String { rawValue }

    public static let redUpRegions: Set<String> = ["CN", "HK", "TW", "JP", "KR", "MO"]

    public static func defaultFor(regionCode: String?) -> UpColorConvention {
        guard let r = regionCode?.uppercased() else { return .greenUp }
        return redUpRegions.contains(r) ? .redUp : .greenUp
    }

    public var label: String {
        switch self {
        case .greenUp: return "Green is up, red is down"
        case .redUp: return "Red is up, green is down (红涨绿跌)"
        }
    }
}

/// Non-colour direction glyph for a change value.
public enum Direction {
    public static func glyph(_ change: Double?) -> String {
        guard let c = change, c != 0 else { return "" }
        return c > 0 ? "▲" : "▼"
    }
}
