import SwiftUI

@main
struct GooseArtApp: App {
    @State private var authenticationService = AuthenticationService()
    
    var body: some Scene {
        WindowGroup {
            Group {
                switch authenticationService.state {
                case .authenticated(let userId):
                    CanvasView()
                    
                case .unauthenticated(let reason):
                    UnauthenticatedView(reason: reason)
                }
            }
        }
    }
}
