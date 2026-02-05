import SwiftUI

enum AuthenticationState: Equatable {
    case authenticated(userId: String)
    case unauthenticated(reason: String?)
}

@Observable
class AuthenticationService {
    var state: AuthenticationState = .unauthenticated(reason: nil)

    func login(userId: String) {
        state = .authenticated(userId: userId)
    }

    func logout() {
        state = .unauthenticated(reason: nil)
    }
}
