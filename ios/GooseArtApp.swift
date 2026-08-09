import SwiftUI

// pass URL(string: "http://localhost:8000") to work against the server
@main
struct GooseArtApp: App {
    @State private var authenticationService = AuthenticationService(
        baseURL: nil
    )

    var body: some Scene {
        WindowGroup {
            switch authenticationService.state {
            case .authenticated(let canvasService):
                CanvasView(
                    placementService: canvasService,
                    logout: authenticationService.logout
                )

            case .unauthenticated(_):
                LoginView(authenticationService: authenticationService)
            }
        }
    }
}
