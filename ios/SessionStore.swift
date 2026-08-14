import Foundation

struct Session: Codable {
    let token: String
    let userId: String
}

enum SessionStore {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.maxbickers.goose-art",
        kSecAttrAccount as String: "canvasToken",
    ]

    static func load() -> Session? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(Session.self, from: data)
    }

    static func save(_ session: Session) {
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = try! JSONEncoder().encode(session)
        _ = SecItemAdd(item as CFDictionary, nil)
    }

    static func clear() {
        SecItemDelete(query as CFDictionary)
    }
}
