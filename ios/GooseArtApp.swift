import SwiftUI
import UserNotifications

// pass nil to work offline, or URL(string: "http://localhost:8000") for a local server
@main
struct GooseArtApp: App {
    @UIApplicationDelegateAdaptor(PushNotificationDelegate.self)
    private var pushNotificationDelegate

    @State private var authenticationService = AuthenticationService(
        baseURL: URL(string: "https://goose-art.maxbickers.com")
    )

    var body: some Scene {
        WindowGroup {
            Group {
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
            // a device token can only arrive after a session asked to register for one,
            // which needs at least an await to get through, so this is always wired first
            .onAppear {
                pushNotificationDelegate.receivedDeviceToken = { deviceToken in
                    authenticationService.receivedDeviceToken(deviceToken)
                }
            }
        }
    }
}

class PushNotificationDelegate: NSObject, UIApplicationDelegate,
    UNUserNotificationCenterDelegate
{
    var receivedDeviceToken: ((String) -> Void)?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication
            .LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // called in response to the registerForRemoteNotifications() that starting a session
    // asks for, and again if iOS ever changes the token. never spontaneously at launch
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let hex = deviceToken.map { byte in String(format: "%02x", byte) }
            .joined()
        receivedDeviceToken?(hex)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("remote notification registration failed: \(error)")
    }

    // the canvas already shows an arriving placement live, so a banner on top of it
    // would be repeating what the user is looking at
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        []
    }
}
