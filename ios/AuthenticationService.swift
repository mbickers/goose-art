import SwiftUI

enum AuthenticationState {
    case authenticated(canvasClient: CanvasClient)
    case unauthenticated(reason: String?)
}

@Observable
class AuthenticationService {
    var state: AuthenticationState = .unauthenticated(reason: nil)

    func login(userId: String) {
        let canvasClient = CanvasClient(
            // TODO: make configurable
            baseURL: URL(string: "http://localhost:8000")!,
            userId: userId,
            deviceId: UUID().uuidString
        )
        Task { await canvasClient.connect() }
        state = .authenticated(canvasClient: canvasClient)
    }

    func logout() {
        state = .unauthenticated(reason: nil)
    }
}
