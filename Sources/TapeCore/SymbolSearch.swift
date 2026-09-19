import Foundation

/// Ranking for the add-instrument dropdown. Local curated matches show instantly; Twelve Data
/// results (one credit per query, US-listed and USD-quoted only) are merged in, and the list is
/// diversified so "gold" surfaces the best stock, ETF, spot metal and token together.
public enum SymbolSearch {
    public static let maxResults = 8
    public static let usExchanges: Set<String> = ["NYSE", "NASDAQ", "NYSE ARCA", "CBOE", "BATS", "AMEX", "NYSE MKT"]

    /// Uppercases and strips anything a Twelve Data symbol cannot contain.
    public static func normalize(_ raw: String) -> String {
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-/ &")
        return String(raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().filter { allowed.contains($0) })
    }

    /// The symbol to add when the user presses return without picking a suggestion.
    public static func rawSymbol(_ raw: String) -> String {
        normalize(raw).replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "&", with: "")
    }

    public static func localMatches(_ query: String) -> [SearchResult] {
        let q = normalize(query)
        guard !q.isEmpty else { return [] }
        let ql = q.lowercased()
        var out: [SearchResult] = []
        for (idx, c) in Curated.all.enumerated() {
            var score = 0
            let tagWords = c.tags.split(separator: " ").map(String.init)
            if c.symbol == q { score = 100 }
            else if c.symbol.replacingOccurrences(of: "/USD", with: "") == q { score = 96 }
            else if c.symbol.hasPrefix(q) { score = 82 - min(10, c.symbol.count - q.count) }
            else if tagWords.contains(ql) { score = 72 }
            else if c.name.lowercased().hasPrefix(ql) { score = 68 }
            else if ql.count >= 2, tagWords.contains(where: { $0.hasPrefix(ql) }) { score = 60 }
            else if ql.count >= 3, c.name.lowercased().contains(ql) { score = 52 }
            if score > 0 {
                out.append(SearchResult(symbol: c.symbol, name: c.name, type: c.type, exchange: nil, score: score, popularity: idx, fromAPI: false))
            }
        }
        return out
    }

    /// Filters Twelve Data hits down to what a US watcher can quote: US exchanges in USD,
    /// plus /USD crypto, metal and forex pairs. One entry per symbol.
    public static func fromAPI(_ hits: [RawSearchHit], query: String) -> [SearchResult] {
        let q = normalize(query)
        var seen = Set<String>()
        var out: [SearchResult] = []
        for hit in hits {
            let sym = hit.symbol
            let type = InstrumentType.from(twelveDataType: hit.instrumentType ?? "", exchange: hit.exchange ?? "")
            let ok: Bool
            switch type {
            case .crypto, .commodity, .forex: ok = sym.hasSuffix("/USD")
            default: ok = usExchanges.contains(hit.exchange ?? "") && ((hit.currency ?? "USD") == "USD" || (hit.currency ?? "").isEmpty)
            }
            guard ok, !seen.contains(sym) else { continue }
            seen.insert(sym)
            var score = sym == q ? 90 : (sym.hasPrefix(q) ? 62 - min(10, sym.count - q.count) : 40)
            if type == .fund || type == .other { score -= 15 }
            out.append(SearchResult(symbol: sym, name: hit.instrumentName ?? sym, type: type, exchange: hit.exchange, score: score, popularity: 1000 + out.count, fromAPI: true))
        }
        return out
    }

    private static func byScore(_ a: SearchResult, _ b: SearchResult) -> Bool {
        if a.score != b.score { return a.score > b.score }
        let ta = InstrumentType.displayOrder.firstIndex(of: a.type) ?? 99
        let tb = InstrumentType.displayOrder.firstIndex(of: b.type) ?? 99
        if ta != tb { return ta < tb }
        return a.popularity < b.popularity
    }

    /// Best overall first, then the best of each other kind (score 65 or more), then the rest by score.
    public static func rank(local: [SearchResult], api: [SearchResult], excluding: Set<String> = []) -> [SearchResult] {
        var bySymbol: [String: SearchResult] = [:]
        for item in local + api {
            if let cur = bySymbol[item.symbol], cur.score >= item.score { continue }
            bySymbol[item.symbol] = item
        }
        let all = bySymbol.values.filter { !excluding.contains($0.symbol) }.sorted(by: byScore)
        guard let top = all.first else { return [] }
        var picked = [top]
        var used: Set<String> = [top.symbol]
        var bests: [SearchResult] = []
        for t in InstrumentType.displayOrder where t != top.type {
            if let best = all.first(where: { $0.type == t && $0.score >= 65 }) { bests.append(best) }
        }
        for b in bests.sorted(by: byScore) where picked.count < maxResults && !used.contains(b.symbol) {
            picked.append(b); used.insert(b.symbol)
        }
        for item in all where picked.count < maxResults && !used.contains(item.symbol) {
            picked.append(item); used.insert(item.symbol)
        }
        return picked
    }
}
