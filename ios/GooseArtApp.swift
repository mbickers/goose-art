import SwiftUI

// Offline dev entry point: no CanvasClient, so no websocket reconnect noise.
// Swap back to the authenticated body below when working against the server.
@main
struct GooseArtApp: App {
    @State private var placementService = FrontendCanvasService()

    var body: some Scene {
        WindowGroup {
            CanvasView(placementService: placementService, logout: nil)
        }
    }
}

//@main
//struct GooseArtApp: App {
//    @State private var authenticationService = AuthenticationService()
//
//    var body: some Scene {
//        WindowGroup {
//            Group {
//                switch authenticationService.state {
//                case .authenticated(let canvasService):
//                    CanvasView(
//                        placementService: canvasService,
//                        logout: {
//                            authenticationService.logout()
//                        })
//
//                case .unauthenticated(_):
//                    LoginView(authenticationService: authenticationService)
//                }
//            }
//        }
//    }
//}
