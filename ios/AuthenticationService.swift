import SwiftUI

enum AuthenticationState {
    case authenticated(canvasClient: CanvasClient)
    case unauthenticated(reason: String?)
}

@Observable
class AuthenticationService {
    var state: AuthenticationState = .unauthenticated(reason: nil)

    // TODO: fix placeholders/remove login call in init
    init() {
        login(userId: "max")
    }

    func login(userId: String) {
        let canvasClient = CanvasClient(
            baseURL: URL(string: "http://localhost:8000")!,
            userId: userId,
            deviceId: "temp",
        )
        state = .authenticated(canvasClient: canvasClient)
    }

    func logout() {
        state = .unauthenticated(reason: nil)
    }
}
