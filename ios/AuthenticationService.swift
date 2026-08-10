import CryptoKit
import SwiftUI

enum AuthenticationState {
    case authenticated(canvasService: DistributedStateMachineClient<[Placement], CanvasAction>)
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

private func loadLocalState(
    token: String
) -> DistributedStateMachineLocalState<[Placement], CanvasAction>? {
    guard
        let data = UserDefaults.standard.data(
            forKey: localStateKey(token: token)
        )
    else { return nil }
    return try? JSONDecoder().decode(
        DistributedStateMachineLocalState<[Placement], CanvasAction>.self,
        from: data
    )
}

private func saveLocalState(
    _ localState: DistributedStateMachineLocalState<[Placement], CanvasAction>,
    token: String
) {
    UserDefaults.standard.set(
        try! JSONEncoder().encode(localState),
        forKey: localStateKey(token: token)
    )
}

@Observable
class AuthenticationService {
    private let baseURL: URL?
    private var canvasConnection:
        AuthenticatedWebSocket<ServerMessage<[Placement]>, ClientMessage<CanvasAction>>?

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
            state = .unauthenticated(reason: "couldn't reach the server.")
            return
        }
        guard response.statusCode == 200 else {
            state = .unauthenticated(reason: "that code didn't work.")
            return
        }
        startSession(token: token)
    }

    private func startSession(token: String) {
        canvasConnection?.disconnect()
        TokenStore.save(token)

        let connection = baseURL.map { baseURL in
            AuthenticatedWebSocket<ServerMessage<[Placement]>, ClientMessage<CanvasAction>>(
                baseURL: baseURL,
                path: "canvas",
                queryItems: [URLQueryItem(name: "deviceId", value: deviceId())],
                token: token,
                onAuthenticationFailed: { [weak self] in
                    Task { @MainActor in
                        self?.logout(reason: "authentication failure")
                    }
                }
            )
        }
        canvasConnection = connection
        state = .authenticated(
            canvasService: DistributedStateMachineClient(
                localState: loadLocalState(token: token)
                    ?? DistributedStateMachineLocalState(initialState: []),
                reduce: reduceCanvas(state:action:),
                connection: connection,
                persistState: { localState in
                    saveLocalState(localState, token: token)
                }
            )
        )
    }

    func logout(reason: String? = nil) {
        canvasConnection?.disconnect()
        canvasConnection = nil
        TokenStore.clear()
        state = .unauthenticated(reason: reason)
    }
}
