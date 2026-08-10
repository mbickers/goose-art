import UIKit
import UserNotifications

// the device token and the signed-in session arrive independently and in either order,
// so both are held until there is enough to register with the server
@MainActor
final class PushNotificationService {
    static let shared = PushNotificationService()

    private var deviceToken: String?
    private var session: (baseURL: URL, token: String)?

    func sessionStarted(baseURL: URL, token: String) {
        session = (baseURL, token)
        Task { await requestAuthorization() }
        registerWithServer()
    }

    // the token stays registered on logout: it is re-pointed at whoever logs in next,
    // and clearing it here would need a network round trip the logout doesn't wait for
    func sessionEnded() {
        session = nil
    }

    func received(deviceToken: String) {
        self.deviceToken = deviceToken
        registerWithServer()
    }

    private func requestAuthorization() async {
        let granted =
            (try? await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound, .badge]
            )) ?? false
        guard granted else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    private func registerWithServer() {
        guard let deviceToken, let session else { return }

        var request = URLRequest(
            url: session.baseURL.appendingPathComponent("deviceToken")
        )
        request.httpMethod = "POST"
        request.setValue(
            "Bearer \(session.token)",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try! JSONEncoder().encode(
            DeviceTokenBody(deviceToken: deviceToken)
        )

        Task {
            _ = try? await URLSession.shared.data(for: request)
        }
    }
}

private struct DeviceTokenBody: Encodable {
    let deviceToken: String
}

class PushNotificationDelegate: NSObject, UIApplicationDelegate,
    UNUserNotificationCenterDelegate
{
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication
            .LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let hex = deviceToken.map { byte in String(format: "%02x", byte) }
            .joined()
        PushNotificationService.shared.received(deviceToken: hex)
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
