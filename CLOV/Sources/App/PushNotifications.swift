import UIKit
import UserNotifications

extension Notification.Name {
    static let clovAPNsToken = Notification.Name("clovAPNsToken")
    static let clovOpenFitCheck = Notification.Name("clovOpenFitCheck")
}

final class CLOVAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// A tapped push can arrive before SwiftUI is listening (cold launch);
    /// CLOVApp drains this once it is.
    private(set) var pendingFitCheckId: UUID?

    func takePendingFitCheckId() -> UUID? {
        defer { pendingFitCheckId = nil }
        return pendingFitCheckId
    }

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func requestPushPermission() {
        Task {
            let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) ?? false
            guard granted else { return }
            await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
        }
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        NotificationCenter.default.post(name: .clovAPNsToken, object: token)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Log.push.error("APNs registration failed: \(error.localizedDescription)")
    }

    /// Show a banner for pushes that arrive while the app is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    /// Open the Fit-Check a tapped push is about.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        guard let payload = PushPayload(userInfo: userInfo) else {
            Log.push.error("Ignoring push tap without a valid fitCheckId")
            return
        }
        await MainActor.run {
            pendingFitCheckId = payload.fitCheckId
            NotificationCenter.default.post(name: .clovOpenFitCheck, object: payload.fitCheckId)
        }
    }
}
