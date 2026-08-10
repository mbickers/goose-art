import CryptoKit
import SwiftUI

enum AuthenticationState {
    case authenticated(canvasService: FrontendCanvasService)
    case unauthenticated(reason: String?)
}

private func deviceId() -> String {
    let key = "deviceId"
    if let existing = UserDefaults.standard.string(forKey: key) {
        return existing
    }
    let newId = UUID().uuidString
    UserDefaults.standard.set(newId, forKey: key)
    return newId
}

// keyed by token so that logging in as someone else doesn't replay their actions,
// and digested so that the token itself stays out of UserDefaults
private func localStateKey(token: String) -> String {
    let digest = SHA256.hash(data: Data(token.utf8))
    let hex = digest.map { byte in String(format: "%02x", byte) }.joined()
    return "canvasLocalState-\(hex.prefix(16))"
}

private func loadLocalState(token: String) -> LocalState? {
    guard
        let data = UserDefaults.standard.data(
            forKey: localStateKey(token: token)
        )
    else { return nil }
    return try? JSONDecoder().decode(LocalState.self, from: data)
}

private func saveLocalState(_ localState: LocalState, token: String) {
    UserDefaults.standard.set(
        try! JSONEncoder().encode(localState),
        forKey: localStateKey(token: token)
    )
}

@Observable
class AuthenticationService {
    private let baseURL: URL?

    var state: AuthenticationState = .unauthenticated(reason: nil)

    init(baseURL: URL?) {
        self.baseURL = baseURL
        if let token = TokenStore.load() {
            login(token: token)
        }
    }

    func login(token: String) {
        TokenStore.save(token)
        let canvasClient = baseURL.map { baseURL in
            CanvasClient(
                baseURL: baseURL,
                token: token,
                deviceId: deviceId(),
                onAuthenticationFailed: { [weak self] in
                    Task { @MainActor in
                        self?.logout(reason: "Authentication failure")
                    }
                }
            )
        }
        state = .authenticated(
            canvasService: FrontendCanvasService(
                canvasClient: canvasClient,
                initialState: loadLocalState(token: token),
                persistState: { localState in
                    saveLocalState(localState, token: token)
                }
            )
        )
    }

    func logout(reason: String? = nil) {
        TokenStore.clear()
        state = .unauthenticated(reason: reason)
    }
}
