import Foundation
import Security
import TapeCore

/// Everything except the API key lives in UserDefaults as JSON. The key lives in the Keychain.
struct Store: @unchecked Sendable {
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    enum Key: String {
        case symbols = "tape.symbols"
        case meta = "tape.meta.v1"
        case quotes = "tape.quotes.v1"
        case series = "tape.series.v1"
        case selected = "tape.selected"
        case timeframe = "tape.tf"
        case failures = "tape.failures.v1"
        case upColor = "tape.upColor"
        case searchCache = "tape.search.v1"
        case creditsMinute = "tape.credits.min"
        case creditsDay = "tape.credits.day"
    }

    func load<T: Decodable>(_ key: Key, as type: T.Type) -> T? {
        guard let data = defaults.data(forKey: key.rawValue) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    func save<T: Encodable>(_ value: T, for key: Key) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key.rawValue) }
    }

    func remove(_ key: Key) { defaults.removeObject(forKey: key.rawValue) }
    func has(_ key: Key) -> Bool { defaults.object(forKey: key.rawValue) != nil }
}

/// Governor counters in UserDefaults, so a relaunch keeps the minute and day estimates.
struct DefaultsGovernorStore: GovernorStore {
    let store: Store
    func loadMinute() -> GovernorMinute? { store.load(.creditsMinute, as: GovernorMinute.self) }
    func saveMinute(_ m: GovernorMinute) { store.save(m, for: .creditsMinute) }
    func loadDay() -> GovernorDay? { store.load(.creditsDay, as: GovernorDay.self) }
    func saveDay(_ d: GovernorDay) { store.save(d, for: .creditsDay) }
}

/// Small Keychain wrapper for the Twelve Data key. Generic password, this device only,
/// readable only while the device is unlocked: the app never needs the key in the
/// background, so the tighter class costs nothing (Kimi review M10).
enum KeychainStore {
    private static let service = "com.tape.app.twelvedata"
    private static let account = "apikey"

    static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func write(_ value: String) -> Bool {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let update = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if update == errSecSuccess { return true }
        if update == errSecItemNotFound {
            var add = query
            for (k, v) in attrs { add[k] = v }
            return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
        }
        return false
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
