import CryptoKit
import SwiftUI
import UserNotifications

enum AuthenticationState {
    case authenticated(
        canvasService: DistributedStateMachineClient<[Placement], CanvasAction>,
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
        // a stored session is trusted without asking the server, so the app still opens
        // with its local canvas offline. a revoked one is caught by the websocket 403
        if let session = SessionStore.load() {
            startSession(session)
        }
    }

    // checks the token before authenticating, so a bad code shows an error on the login
    // screen instead of flashing the canvas and being kicked back by the websocket
    func login(token: String) async {
        // offline there is nobody to name the user, so the code they typed stands in
        guard let baseURL else {
            startSession(Session(token: token, userId: token))
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
        Task { await requestNotificationAuthorization() }

        canvasConnection = connection
        state = .authenticated(
            canvasService: DistributedStateMachineClient(
                localState: loadLocalState(token: token)
                    ?? DistributedStateMachineLocalState(initialState: []),
                reduce: reduceCanvas(state:action:),
                connection: connection,
                persistState: { localState in
                    saveLocalState(localState, token: token)
                },
                // our own placements never appear in this diff: apply() adds them to the
                // state immediately, so by the time the server echoes one back it is in
                // both the before and after state. a placement id that is new here was
                // made on some other device
                onServerUpdate: { previousPlacements, placements, isFirstUpdateOfSession in
                    // what was already on the canvas when the session opened isn't an
                    // arrival, so logging in to a canvas full of emoji stays quiet
                    guard !isFirstUpdateOfSession else { return }
                    let previousIds = Set(previousPlacements.map(\.id))
                    if placements.contains(where: { placement in
                        !previousIds.contains(placement.id)
                    }) {
                        MessageSound.playIfForeground()
                    }
                }
            ),
            userId: session.userId
        )
    }

    // the server reads a live canvas connection as the user watching placements land, and
    // so notifies them of nothing while one is open. a suspended app can hold its socket
    // open long after the user stopped looking, so the connection follows the scene
    // rather than the session
    func enteredForeground() {
        canvasConnection?.connect()
    }

    func enteredBackground() {
        canvasConnection?.disconnect()
    }

    func logout(reason: String? = nil) {
        canvasConnection?.disconnect()
        canvasConnection = nil
        SessionStore.clear()
        state = .unauthenticated(reason: reason)
    }

    // asking again once the user has answered returns that answer without prompting them
    // a second time, so this can run on every session
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
