import Foundation

struct Session: Codable {
    let token: String
    let userId: String
}

// the access token is a credential, so the session lives in the keychain rather than
// UserDefaults, which is unencrypted and included in device backups
enum SessionStore {
    // the account name predates storing the whole session, and is kept so that the
    // bare token written by older builds is overwritten rather than left behind
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.maxbickers.goose-art",
        kSecAttrAccount as String: "canvasToken",
    ]

    // a bare token from an older build fails to decode, which logs that install out once
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
