@preconcurrency import Foundation
#if canImport(FoundationNetworking)
@preconcurrency import FoundationNetworking
#endif

/// Minimal HTTP seam so the client can be tested without a network.
public protocol HTTPTransport: Sendable {
    func get(_ url: URL, headers: [String: String]) async throws -> (Data, Int)
}

public struct URLSessionTransport: HTTPTransport, @unchecked Sendable {
    public let session: URLSession
    public let timeout: TimeInterval

    public init(timeout: TimeInterval = 8) {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = timeout
        cfg.timeoutIntervalForResource = timeout * 2
        #if !canImport(FoundationNetworking)
        cfg.waitsForConnectivity = false
        #endif
        self.session = URLSession(configuration: cfg)
        self.timeout = timeout
    }

    public func get(_ url: URL, headers: [String: String]) async throws -> (Data, Int) {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = timeout
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        #if canImport(FoundationNetworking)
        // swift-corelibs-foundation has no async `data(for:)`; the package only needs this
        // path so `swift test` runs on Linux CI (Kimi review M12).
        let box = TaskBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<(Data, Int), Error>) in
                let task = session.dataTask(with: req) { data, response, error in
                    if let error { cont.resume(throwing: error); return }
                    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                    cont.resume(returning: (data ?? Data(), code))
                }
                box.set(task)
                task.resume()
            }
        } onCancel: {
            box.cancel()
        }
        #else
        let (data, response) = try await session.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (data, code)
        #endif
    }
}

#if canImport(FoundationNetworking)
/// Holds a data task so cancellation can reach it from the continuation path above.
final class TaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionDataTask?
    private var cancelled = false
    func set(_ t: URLSessionDataTask) {
        lock.lock(); defer { lock.unlock() }
        task = t
        if cancelled { t.cancel() }
    }
    func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        task?.cancel()
    }
}
#endif

/// Twelve Data REST client. The key travels only in the `Authorization: apikey KEY` header,
/// never in a URL. The web build needs a query-parameter fallback because a browser cannot
/// tell a CORS refusal from an outage; a native client has no such ambiguity, so there is no
/// fallback here and nothing that could demote the key into request logs (Kimi review C2).
public actor TwelveDataClient {
    public static let baseURL = URL(string: "https://api.twelvedata.com")!

    private var apiKey: String
    private let transport: HTTPTransport

    public init(apiKey: String, transport: HTTPTransport = URLSessionTransport()) {
        self.apiKey = apiKey
        self.transport = transport
    }

    public func updateKey(_ key: String) { apiKey = key }

    // MARK: endpoints

    /// One batched call; each symbol costs one credit. Unknown symbols come back as errors
    /// inside the map, not as a failed request. Callers keep batches within the governor's
    /// per-minute limit (see `Array.chunked(by:)`).
    public func quotes(symbols: [String]) async throws -> [String: Result<Quote, TapeError>] {
        guard !symbols.isEmpty else { return [:] }
        let json = try await requestJSON(path: "/quote", params: ["symbol": symbols.joined(separator: ","), "timezone": "America/New_York"])
        var out: [String: Result<Quote, TapeError>] = [:]
        let decoder = JSONDecoder()
        if let obj = json as? [String: Any] {
            if obj["symbol"] is String {
                if let data = try? JSONSerialization.data(withJSONObject: obj), let q = try? decoder.decode(Quote.self, from: data) {
                    out[q.symbol] = .success(q)
                }
            } else {
                for s in symbols {
                    guard let entry = obj[s] as? [String: Any] else { out[s] = .failure(.api(code: 404, message: "No data for this symbol")); continue }
                    if let status = entry["status"] as? String, status == "error" {
                        out[s] = .failure(.api(code: (entry["code"] as? Int) ?? 400, message: (entry["message"] as? String) ?? "No data for this symbol"))
                        continue
                    }
                    if let data = try? JSONSerialization.data(withJSONObject: entry), var q = try? decoder.decode(Quote.self, from: data) {
                        if q.symbol.isEmpty { q.symbol = s }
                        out[s] = .success(q)
                    } else {
                        out[s] = .failure(.decoding)
                    }
                }
            }
        }
        for s in symbols where out[s] == nil { out[s] = .failure(.api(code: 404, message: "No data for this symbol")) }
        return out
    }

    /// Bars come back newest first, exactly as Twelve Data sends them.
    public func timeSeries(symbol: String, spec: TimeframeSpec) async throws -> [Bar] {
        var params = ["symbol": symbol, "interval": spec.interval, "outputsize": String(spec.outputSize)]
        if spec.wantsTimezone { params["timezone"] = "America/New_York" }
        let json = try await requestJSON(path: "/time_series", params: params)
        guard let obj = json as? [String: Any], let values = obj["values"] else { throw TapeError.decoding }
        let data = try JSONSerialization.data(withJSONObject: values)
        return try JSONDecoder().decode([Bar].self, from: data)
    }

    /// One credit per request. Results are not ranked by popularity; `SymbolSearch` does that.
    public func symbolSearch(query: String, outputSize: Int = 60) async throws -> [RawSearchHit] {
        let json = try await requestJSON(path: "/symbol_search", params: ["symbol": query, "outputsize": String(outputSize)])
        guard let obj = json as? [String: Any], let data = obj["data"] else { return [] }
        let bytes = try JSONSerialization.data(withJSONObject: data)
        return try JSONDecoder().decode([RawSearchHit].self, from: bytes)
    }

    /// One-credit check that a key is accepted (Kimi review U2). Returns the quote on success.
    public func validateKey(probeSymbol: String = "SPY") async throws -> Quote {
        let result = try await quotes(symbols: [probeSymbol])
        switch result[probeSymbol] {
        case .success(let q)?: return q
        case .failure(let e)?: throw e
        case nil: throw TapeError.decoding
        }
    }

    // MARK: plumbing

    private func makeURL(path: String, params: [String: String]) -> URL {
        var comps = URLComponents(url: TwelveDataClient.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        comps.queryItems = params.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return comps.url!
    }

    /// Maps an HTTP status onto a `TapeError` before the body is trusted, so an intermediary's
    /// 429 or 403 page reaches the backoff and auth paths instead of reading as noise (Kimi review C5).
    static func error(forStatus code: Int) -> TapeError? {
        switch code {
        case 200..<300, 0: return nil
        case 401, 403: return .unauthorized("The data service rejected the key (HTTP \(code)).")
        case 429: return .rateLimited("HTTP 429")
        case 500..<600: return .network("The data service returned HTTP \(code).")
        default: return .api(code: code, message: "HTTP \(code)")
        }
    }

    private func requestJSON(path: String, params: [String: String]) async throws -> Any {
        let url = makeURL(path: path, params: params)
        let headers: [String: String] = ["Authorization": "apikey \(apiKey)"]
        let data: Data
        let status: Int
        do {
            let response = try await transport.get(url, headers: headers)
            data = response.0
            status = response.1
        } catch is CancellationError {
            throw TapeError.cancelled
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw TapeError.cancelled
        } catch {
            throw TapeError.network(error.localizedDescription)
        }
        if let e = TwelveDataClient.error(forStatus: status) { throw e }
        guard let json = try? JSONSerialization.jsonObject(with: data) else { throw TapeError.decoding }
        if let obj = json as? [String: Any], let s = obj["status"] as? String, s == "error" {
            let code = (obj["code"] as? Int) ?? 0
            let message = (obj["message"] as? String) ?? "API error"
            switch code {
            case 401, 403: throw TapeError.unauthorized(message)
            case 429: throw TapeError.rateLimited(message)
            default: throw TapeError.api(code: code, message: message)
            }
        }
        return json
    }
}
