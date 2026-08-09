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

// keyed by user so that logging in as someone else doesn't replay their actions
private func localStateKey(userId: String) -> String {
    return "canvasLocalState-\(userId)"
}

private func loadLocalState(userId: String) -> LocalState? {
    guard
        let data = UserDefaults.standard.data(
            forKey: localStateKey(userId: userId)
        )
    else { return nil }
    return try? JSONDecoder().decode(LocalState.self, from: data)
}

private func saveLocalState(_ localState: LocalState, userId: String) {
    UserDefaults.standard.set(
        try! JSONEncoder().encode(localState),
        forKey: localStateKey(userId: userId)
    )
}

@Observable
class AuthenticationService {
    private let baseURL: URL?

    var state: AuthenticationState = .unauthenticated(reason: nil)

    // TODO: fix placeholders/remove login call in init
    init(baseURL: URL?) {
        self.baseURL = baseURL
        login(userId: "max")
    }

    func login(userId: String) {
        let canvasClient = baseURL.map { baseURL in
            CanvasClient(
                baseURL: baseURL,
                userId: userId,
                deviceId: deviceId()
            )
        }
        state = .authenticated(
            canvasService: FrontendCanvasService(
                canvasClient: canvasClient,
                initialState: loadLocalState(userId: userId),
                persistState: { localState in
                    saveLocalState(localState, userId: userId)
                }
            )
        )
    }

    func logout() {
        state = .unauthenticated(reason: nil)
    }
}
