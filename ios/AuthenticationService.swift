import CryptoKit
import SwiftUI
import UserNotifications

enum AuthenticationState {
    case authenticated(
        canvasService: DistributedStateMachineClient<CanvasState, CanvasAction>,
        userId: String
    )
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

// keyed by token so that logging in as someone else doesn't replay their actions
private func localStateKey(token: String) -> String {
    let digest = SHA256.hash(data: Data(token.utf8))
    let hex = digest.map { byte in String(format: "%02x", byte) }.joined()
    return "canvasLocalState-\(hex.prefix(16))"
}

private func loadLocalState(
    token: String
) -> DistributedStateMachineLocalState<CanvasState, CanvasAction>? {
    guard
        let data = UserDefaults.standard.data(
            forKey: localStateKey(token: token)
        )
    else { return nil }
    // state we can't decode is ignored
    return try? JSONDecoder().decode(
        DistributedStateMachineLocalState<CanvasState, CanvasAction>.self,
        from: data
    )
}

private func saveLocalState(
    _ localState: DistributedStateMachineLocalState<CanvasState, CanvasAction>,
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
        AuthenticatedWebSocket<ServerMessage<CanvasState>, ClientMessage<CanvasAction>>?

    var state: AuthenticationState = .unauthenticated(reason: nil)

    init(baseURL: URL?) {
        self.baseURL = baseURL
        // a stored session is trusted without asking the server, so the app still opens
        // with its local canvas offline. a revoked one is caught by the websocket 403
        if let session = SessionStore.load() {
            startSession(session)
        }
    }

    func login(token: String) async {
        guard let baseURL else {
            startSession(Session(token: token, userId: "unknown until reconnect"))
            return
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("login"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let result = try? await URLSession.shared.data(for: request)

        guard let (data, response) = result, let response = response as? HTTPURLResponse
        else {
            state = .unauthenticated(reason: "couldn't reach the server.")
            return
        }
        guard response.statusCode == 200 else {
            state = .unauthenticated(reason: "that code didn't work.")
            return
        }
        guard let body = try? JSONDecoder().decode(LoginResponse.self, from: data) else {
            state = .unauthenticated(reason: "couldn't reach the server.")
            return
        }
        startSession(Session(token: token, userId: body.userId))
    }

    private func startSession(_ session: Session) {
        let token = session.token
        canvasConnection?.disconnect()
        SessionStore.save(session)

        let connection = baseURL.map { baseURL in
            AuthenticatedWebSocket<ServerMessage<CanvasState>, ClientMessage<CanvasAction>>(
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
        Task { await requestNotificationAuthorization() }

        canvasConnection = connection
        state = .authenticated(
            canvasService: DistributedStateMachineClient(
                localState: loadLocalState(token: token)
                    ?? DistributedStateMachineLocalState(initialState: .empty),
                reduce: reduceCanvas(state:action:),
                connection: connection,
                persistState: { localState in
                    saveLocalState(localState, token: token)
                },
                // our own placements never appear in this diff: apply() adds them to the
                // state immediately, so by the time the server echoes one back it is in
                // both the before and after state. a placement id that is new here was
                // made on some other device
                onServerUpdate: { previousCanvas, canvas, isFirstUpdateOfSession in
                    guard !isFirstUpdateOfSession else { return }
                    let previousIds = Set(previousCanvas.placements.map(\.id))
                    if canvas.placements.contains(where: { placement in
                        !previousIds.contains(placement.id)
                    }) {
                        MessageSound.playIfForeground()
                    }
                }
            ),
            userId: session.userId
        )
    }

    func enteredForeground() {
        canvasConnection?.connect()
    }

    func enteredBackground() {
        // disconenct so that server knows not to send us notifications when app is not in foreground
        canvasConnection?.disconnect()
    }

    func logout(reason: String? = nil) {
        canvasConnection?.disconnect()
        canvasConnection = nil
        SessionStore.clear()
        state = .unauthenticated(reason: reason)
    }

    private func requestNotificationAuthorization() async {
        guard baseURL != nil else { return }

        let granted =
            (try? await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound, .badge]
            )) ?? false
        guard granted else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    // reads the token back rather than holding it, so that a session cleared by logout
    // stops this from registering a device against the user who just left
    func receivedDeviceNotificationToken(_ deviceNotificationToken: String) {
        guard let baseURL, let token = SessionStore.load()?.token else { return }

        var request = URLRequest(
            url: baseURL.appendingPathComponent("deviceNotificationToken")
        )
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try! JSONEncoder().encode(
            DeviceNotificationTokenBody(
                deviceNotificationToken: deviceNotificationToken
            )
        )

        Task {
            _ = try? await URLSession.shared.data(for: request)
        }
    }
}

private struct DeviceNotificationTokenBody: Encodable {
    let deviceNotificationToken: String
}

private struct LoginResponse: Decodable {
    let userId: String
}
