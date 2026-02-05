import SwiftUI

@main
struct GooseArtApp: App {
    @State private var authenticationService = AuthenticationService()

    var body: some Scene {
        WindowGroup {
            Group {
                switch authenticationService.state {
                case .authenticated(let canvasClient):
                    CanvasView(canvasClient: canvasClient, logout: {
                        authenticationService.logout()
                    })

                case .unauthenticated(_):
                    LoginView(authenticationService: authenticationService)
                }
            }
        }
    }
}
