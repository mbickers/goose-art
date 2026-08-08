import SwiftUI

enum AuthenticationState {
    case authenticated(canvasService: FrontendCanvasService)
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
        let key = "deviceId"
        let deviceId =
            UserDefaults.standard.string(forKey: key)
            ?? {
                let newId = UUID().uuidString
                UserDefaults.standard.set(newId, forKey: key)
                return newId
            }()

        let canvasClient = CanvasClient(
            baseURL: URL(string: "http://localhost:8000")!,
            userId: userId,
            deviceId: deviceId
        )
        state = .authenticated(
            canvasService: FrontendCanvasService(canvasClient: canvasClient)
        )
    }

    func logout() {
        state = .unauthenticated(reason: nil)
    }
}
