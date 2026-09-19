import Foundation

/// Built-in list of widely watched instruments, matched instantly and for free while the
/// Twelve Data search is in flight. Every entry was checked against Twelve Data's symbol
/// search on 2026-09-19. Order matters: earlier rows win ties as the more popular pick.
public struct CuratedEntry: Sendable {
    public let symbol: String
    public let name: String
    public let type: InstrumentType
    public let tags: String
    public var instrument: Instrument { Instrument(symbol: symbol, name: name, type: type) }
}

public enum Curated {
    public static let all: [CuratedEntry] = [
        CuratedEntry(symbol: "SPY", name: "SPDR S&P 500 ETF", type: .etf, tags: "sp500 s&p 500 index market spx"),
        CuratedEntry(symbol: "VOO", name: "Vanguard S&P 500 ETF", type: .etf, tags: "sp500 s&p 500 index vanguard"),
        CuratedEntry(symbol: "QQQ", name: "Invesco QQQ Trust", type: .etf, tags: "nasdaq 100 tech index"),
        CuratedEntry(symbol: "DIA", name: "SPDR Dow Jones Industrial Average ETF", type: .etf, tags: "dow jones index"),
        CuratedEntry(symbol: "IWM", name: "iShares Russell 2000 ETF", type: .etf, tags: "russell small cap index"),
        CuratedEntry(symbol: "VTI", name: "Vanguard Total Stock Market ETF", type: .etf, tags: "total market vanguard"),
        CuratedEntry(symbol: "GLD", name: "SPDR Gold Shares", type: .etf, tags: "gold bullion metal"),
        CuratedEntry(symbol: "IAU", name: "iShares Gold Trust", type: .etf, tags: "gold bullion metal"),
        CuratedEntry(symbol: "GDX", name: "VanEck Gold Miners ETF", type: .etf, tags: "gold miners metal"),
        CuratedEntry(symbol: "SLV", name: "iShares Silver Trust", type: .etf, tags: "silver metal"),
        CuratedEntry(symbol: "USO", name: "United States Oil Fund", type: .etf, tags: "oil crude wti energy"),
        CuratedEntry(symbol: "UNG", name: "United States Natural Gas Fund", type: .etf, tags: "natural gas natgas energy"),
        CuratedEntry(symbol: "XLE", name: "Energy Select Sector SPDR", type: .etf, tags: "energy oil sector"),
        CuratedEntry(symbol: "XLF", name: "Financial Select Sector SPDR", type: .etf, tags: "financials banks sector"),
        CuratedEntry(symbol: "XLK", name: "Technology Select Sector SPDR", type: .etf, tags: "technology tech sector"),
        CuratedEntry(symbol: "SMH", name: "VanEck Semiconductor ETF", type: .etf, tags: "semiconductors chips semis"),
        CuratedEntry(symbol: "TLT", name: "iShares 20+ Year Treasury Bond ETF", type: .etf, tags: "treasury bonds rates"),
        CuratedEntry(symbol: "ARKK", name: "ARK Innovation ETF", type: .etf, tags: "ark innovation growth"),
        CuratedEntry(symbol: "TQQQ", name: "ProShares UltraPro QQQ", type: .etf, tags: "nasdaq leveraged 3x bull"),
        CuratedEntry(symbol: "SQQQ", name: "ProShares UltraPro Short QQQ", type: .etf, tags: "nasdaq leveraged 3x bear short"),
        CuratedEntry(symbol: "IBIT", name: "iShares Bitcoin Trust ETF", type: .etf, tags: "bitcoin btc crypto"),
        CuratedEntry(symbol: "FBTC", name: "Fidelity Wise Origin Bitcoin Fund", type: .etf, tags: "bitcoin btc crypto"),
        CuratedEntry(symbol: "BITO", name: "ProShares Bitcoin Strategy ETF", type: .etf, tags: "bitcoin btc crypto futures"),
        CuratedEntry(symbol: "ETHA", name: "iShares Ethereum Trust ETF", type: .etf, tags: "ethereum eth crypto"),
        CuratedEntry(symbol: "AAPL", name: "Apple", type: .stock, tags: "apple iphone"),
        CuratedEntry(symbol: "MSFT", name: "Microsoft", type: .stock, tags: "microsoft windows azure"),
        CuratedEntry(symbol: "NVDA", name: "NVIDIA", type: .stock, tags: "nvidia chips semis gpu ai"),
        CuratedEntry(symbol: "AMZN", name: "Amazon", type: .stock, tags: "amazon aws"),
        CuratedEntry(symbol: "GOOGL", name: "Alphabet (Class A)", type: .stock, tags: "google alphabet"),
        CuratedEntry(symbol: "META", name: "Meta Platforms", type: .stock, tags: "facebook instagram meta"),
        CuratedEntry(symbol: "TSLA", name: "Tesla", type: .stock, tags: "tesla ev"),
        CuratedEntry(symbol: "BRK.B", name: "Berkshire Hathaway (Class B)", type: .stock, tags: "berkshire buffett"),
        CuratedEntry(symbol: "JPM", name: "JPMorgan Chase", type: .stock, tags: "jpmorgan bank"),
        CuratedEntry(symbol: "V", name: "Visa", type: .stock, tags: "visa payments"),
        CuratedEntry(symbol: "MA", name: "Mastercard", type: .stock, tags: "mastercard payments"),
        CuratedEntry(symbol: "UNH", name: "UnitedHealth Group", type: .stock, tags: "unitedhealth health insurance"),
        CuratedEntry(symbol: "XOM", name: "Exxon Mobil", type: .stock, tags: "exxon oil energy"),
        CuratedEntry(symbol: "LLY", name: "Eli Lilly", type: .stock, tags: "lilly pharma"),
        CuratedEntry(symbol: "JNJ", name: "Johnson & Johnson", type: .stock, tags: "johnson pharma"),
        CuratedEntry(symbol: "NVO", name: "Novo Nordisk (ADR)", type: .stock, tags: "novo nordisk pharma"),
        CuratedEntry(symbol: "WMT", name: "Walmart", type: .stock, tags: "walmart retail"),
        CuratedEntry(symbol: "COST", name: "Costco", type: .stock, tags: "costco retail"),
        CuratedEntry(symbol: "HD", name: "Home Depot", type: .stock, tags: "home depot retail"),
        CuratedEntry(symbol: "NFLX", name: "Netflix", type: .stock, tags: "netflix streaming"),
        CuratedEntry(symbol: "AMD", name: "Advanced Micro Devices", type: .stock, tags: "amd chips semis"),
        CuratedEntry(symbol: "INTC", name: "Intel", type: .stock, tags: "intel chips semis"),
        CuratedEntry(symbol: "AVGO", name: "Broadcom", type: .stock, tags: "broadcom chips semis"),
        CuratedEntry(symbol: "TSM", name: "Taiwan Semiconductor (ADR)", type: .stock, tags: "tsmc chips semis"),
        CuratedEntry(symbol: "ORCL", name: "Oracle", type: .stock, tags: "oracle cloud"),
        CuratedEntry(symbol: "CRM", name: "Salesforce", type: .stock, tags: "salesforce cloud"),
        CuratedEntry(symbol: "ADBE", name: "Adobe", type: .stock, tags: "adobe software"),
        CuratedEntry(symbol: "DIS", name: "Walt Disney", type: .stock, tags: "disney media"),
        CuratedEntry(symbol: "BA", name: "Boeing", type: .stock, tags: "boeing aerospace"),
        CuratedEntry(symbol: "NKE", name: "Nike", type: .stock, tags: "nike apparel"),
        CuratedEntry(symbol: "MCD", name: "McDonald's", type: .stock, tags: "mcdonalds restaurants"),
        CuratedEntry(symbol: "KO", name: "Coca-Cola", type: .stock, tags: "coca cola beverages"),
        CuratedEntry(symbol: "PEP", name: "PepsiCo", type: .stock, tags: "pepsi beverages"),
        CuratedEntry(symbol: "PG", name: "Procter & Gamble", type: .stock, tags: "procter gamble consumer"),
        CuratedEntry(symbol: "PFE", name: "Pfizer", type: .stock, tags: "pfizer pharma"),
        CuratedEntry(symbol: "BAC", name: "Bank of America", type: .stock, tags: "bank of america"),
        CuratedEntry(symbol: "GS", name: "Goldman Sachs", type: .stock, tags: "goldman sachs bank"),
        CuratedEntry(symbol: "COIN", name: "Coinbase", type: .stock, tags: "coinbase crypto exchange bitcoin"),
        CuratedEntry(symbol: "MSTR", name: "Strategy (MicroStrategy)", type: .stock, tags: "microstrategy bitcoin btc"),
        CuratedEntry(symbol: "HOOD", name: "Robinhood", type: .stock, tags: "robinhood broker"),
        CuratedEntry(symbol: "PLTR", name: "Palantir", type: .stock, tags: "palantir ai data"),
        CuratedEntry(symbol: "UBER", name: "Uber", type: .stock, tags: "uber rideshare"),
        CuratedEntry(symbol: "SOFI", name: "SoFi Technologies", type: .stock, tags: "sofi fintech"),
        CuratedEntry(symbol: "F", name: "Ford Motor", type: .stock, tags: "ford auto"),
        CuratedEntry(symbol: "GM", name: "General Motors", type: .stock, tags: "gm auto"),
        CuratedEntry(symbol: "NOK", name: "Nokia (ADR)", type: .stock, tags: "nokia telecom"),
        CuratedEntry(symbol: "BABA", name: "Alibaba (ADR)", type: .stock, tags: "alibaba china ecommerce"),
        CuratedEntry(symbol: "BTC/USD", name: "Bitcoin", type: .crypto, tags: "bitcoin btc crypto"),
        CuratedEntry(symbol: "ETH/USD", name: "Ethereum", type: .crypto, tags: "ethereum eth ether crypto"),
        CuratedEntry(symbol: "SOL/USD", name: "Solana", type: .crypto, tags: "solana sol crypto"),
        CuratedEntry(symbol: "XRP/USD", name: "XRP", type: .crypto, tags: "xrp ripple crypto"),
        CuratedEntry(symbol: "DOGE/USD", name: "Dogecoin", type: .crypto, tags: "doge dogecoin crypto"),
        CuratedEntry(symbol: "LTC/USD", name: "Litecoin", type: .crypto, tags: "litecoin ltc crypto"),
        CuratedEntry(symbol: "BNB/USD", name: "BNB", type: .crypto, tags: "bnb binance coin crypto"),
        CuratedEntry(symbol: "AVAX/USD", name: "Avalanche", type: .crypto, tags: "avalanche avax crypto"),
        CuratedEntry(symbol: "LINK/USD", name: "Chainlink", type: .crypto, tags: "chainlink link crypto"),
        CuratedEntry(symbol: "PAXG/USD", name: "PAX Gold", type: .crypto, tags: "gold paxg token crypto"),
        CuratedEntry(symbol: "XAU/USD", name: "Gold spot", type: .commodity, tags: "gold spot bullion metal xau"),
        CuratedEntry(symbol: "XAG/USD", name: "Silver spot", type: .commodity, tags: "silver spot metal xag"),
        CuratedEntry(symbol: "XPT/USD", name: "Platinum spot", type: .commodity, tags: "platinum spot metal"),
        CuratedEntry(symbol: "XPD/USD", name: "Palladium spot", type: .commodity, tags: "palladium spot metal")
    ]

    public static func entry(for symbol: String) -> Instrument? {
        all.first { $0.symbol == symbol }?.instrument
    }
}
