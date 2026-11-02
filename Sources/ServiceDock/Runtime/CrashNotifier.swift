import Foundation
import UserNotifications

/// Posts "service died" notifications and reports which service the user clicked.
@MainActor
final class CrashNotifier: NSObject {
    nonisolated static let serviceKey = "serviceID"

    /// `UNUserNotificationCenter` crashes outside an app bundle (e.g. `swift run`).
    static var isAvailable: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }

    private var onOpen: (@MainActor (UUID) -> Void)?
    private var didRequestPermission = false

    func activate(onOpen: @escaping @MainActor (UUID) -> Void) {
        guard Self.isAvailable else { return }
        self.onOpen = onOpen
        UNUserNotificationCenter.current().delegate = self
    }

    func post(serviceID: UUID, title: String, body: String) {
        guard Self.isAvailable else { return }
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = serviceID.uuidString
        content.userInfo = [Self.serviceKey: serviceID.uuidString]
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        let needsPermission = !didRequestPermission
        didRequestPermission = true
        Task {
            if needsPermission { _ = try? await center.requestAuthorization(options: [.alert, .sound]) }
            try? await center.add(request)
        }
    }

    private func open(_ id: UUID) {
        onOpen?(id)
    }
}

extension CrashNotifier: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        guard let text = response.notification.request.content.userInfo[Self.serviceKey] as? String,
              let id = UUID(uuidString: text) else { return }
        await open(id)
    }

    /// Show the banner even while ServiceDock is the active app.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
