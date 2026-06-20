import Foundation
import Security

struct KeychainHelper {
    static let shared = KeychainHelper()
    private let service = "com.xonora.app"
    private let tokenAccount = "access-token"
    private let usernameAccount = "saved-username"
    private let serverAccount = "saved-server"

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
    }

    private func save(key: String, data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
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
        SecItemDelete(query as CFDictionary)
    }
}
