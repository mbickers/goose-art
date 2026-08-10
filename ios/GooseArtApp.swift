import SwiftUI

// pass nil to work offline, or URL(string: "http://localhost:8000") for a local server
@main
struct GooseArtApp: App {
    @State private var authenticationService = AuthenticationService(
        baseURL: URL(string: "https://goose-art.maxbickers.com")
    )

    var body: some Scene {
        WindowGroup {
            switch authenticationService.state {
            case .authenticated(let canvasService):
                CanvasView(
                    placementService: canvasService,
                    logout: { authenticationService.logout() }
                )

            case .unauthenticated(_):
                LoginView(authenticationService: authenticationService)
            }
        }
    }
}
