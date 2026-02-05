import SwiftUI

@main
struct GooseArtApp: App {
    @State private var authenticationService = AuthenticationService()
    
    var body: some Scene {
        WindowGroup {
            Group {
                switch authenticationService.authenticationState {
                case .authenticated(let userId):
                    CanvasView {
                        authenticationService.logout(reason: "User logged out")
                    }
                    
                case .unauthenticated(let reason):
                    UnauthenticatedView(authenticationService: authenticationService, reason: reason)
                }
            }
        }
    }
}
