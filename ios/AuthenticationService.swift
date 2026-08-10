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
    private var canvasClient: CanvasClient?

    var state: AuthenticationState = .unauthenticated(reason: nil)

    init(baseURL: URL?) {
        self.baseURL = baseURL
        // a stored token is trusted without asking the server, so the app still opens
        // with its local canvas offline. a revoked one is caught by the websocket 403
        if let token = TokenStore.load() {
            startSession(token: token)
        }
    }

    // checks the token before authenticating, so a bad code shows an error on the login
    // screen instead of flashing the canvas and being kicked back by the websocket
    func login(token: String) async {
        guard let baseURL else {
            startSession(token: token)
            return
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("login"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let response = try? await URLSession.shared.data(for: request).1

        guard let response = response as? HTTPURLResponse else {
            state = .unauthenticated(reason: "Couldn't reach the server.")
            return
        }
        guard response.statusCode == 200 else {
            state = .unauthenticated(reason: "That code didn't work.")
            return
        }
        startSession(token: token)
    }

    private func startSession(token: String) {
        canvasClient?.disconnect()
        TokenStore.save(token)

        let client = baseURL.map { baseURL in
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
        canvasClient = client
        state = .authenticated(
            canvasService: FrontendCanvasService(
                canvasClient: client,
                initialState: loadLocalState(token: token),
                persistState: { localState in
                    saveLocalState(localState, token: token)
                }
            )
        )
    }

    func logout(reason: String? = nil) {
        canvasClient?.disconnect()
        canvasClient = nil
        TokenStore.clear()
        state = .unauthenticated(reason: reason)
    }
}
