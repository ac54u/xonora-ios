import Foundation
import Security

struct KeychainHelper {
    static let shared = KeychainHelper()
    private let service = "com.xonora.app"
    private let tokenAccount = "access-token"
    private let usernameAccount = "saved-username"
    private let serverAccount = "saved-server"
    private let clientIdAccount = "sendspin-client-id"
    private let playerNameAccount = "sendspin-player-name"

    func saveToken(_ token: String) {
        save(key: tokenAccount, data: Data(token.utf8))
    }

    func getToken() -> String? {
        guard let data = load(key: tokenAccount) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func deleteToken() {
        delete(key: tokenAccount)
    }

    func saveUsername(_ username: String) {
        save(key: usernameAccount, data: Data(username.utf8))
    }

    func getUsername() -> String? {
        guard let data = load(key: usernameAccount) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func deleteUsername() {
        delete(key: usernameAccount)
    }

    func saveServerURL(_ url: String) {
        save(key: serverAccount, data: Data(url.utf8))
    }

    func getServerURL() -> String? {
        guard let data = load(key: serverAccount) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func deleteServerURL() {
        delete(key: serverAccount)
    }

    func clearAll() {
        deleteToken()
        deleteUsername()
        deleteServerURL()
        // Intentionally keep the Sendspin client id and player name so the device
        // stays the SAME player across logout/login (and reinstalls).
    }

    /// A stable client identifier that survives app reinstalls (the Keychain
    /// persists across delete+install), unlike `UIDevice.identifierForVendor`,
    /// which resets on reinstall and spawned a duplicate player on the server each
    /// time (e.g. "iPhone Pro" → a fresh "iPhone"). On first run we seed it with the
    /// current vendor id so existing installs keep their current player_id.
    func getOrCreateClientId(seedIfMissing seed: @autoclosure () -> String) -> String {
        if let data = load(key: clientIdAccount), let s = String(data: data, encoding: .utf8), !s.isEmpty {
            return s
        }
        let new = seed()
        save(key: clientIdAccount, data: Data(new.utf8))
        return new
    }

    func savePlayerName(_ name: String) {
        save(key: playerNameAccount, data: Data(name.utf8))
    }

    func getPlayerName() -> String? {
        guard let data = load(key: playerNameAccount) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func save(key: String, data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: data
        ]
        let deleteStatus = SecItemDelete(query as CFDictionary)
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
            print("[KeychainHelper] Failed to delete existing item: \(deleteStatus)")
            return
        }
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        if addStatus != errSecSuccess {
            print("[KeychainHelper] Failed to save item: \(addStatus)")
        }
    }

    private func load(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    private func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            print("[KeychainHelper] Failed to delete item: \(status)")
        }
    }
}
