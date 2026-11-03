import Foundation
import os
import UserNotifications

public extension Notification.Name {
    static let daylightNotificationResponse = Notification.Name("daylightNotificationResponse")
}

public final class DaylightNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    public static let shared = DaylightNotificationDelegate()

    private let pendingResponses = OSAllocatedUnfairLock<[[String: String]]>(initialState: [])

    private override init() {}

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo.reduce(into: [String: String]()) { result, item in
            if let key = item.key as? String, let value = item.value as? String {
                result[key] = value
            }
        }
        pendingResponses.withLock { $0.append(userInfo) }
        NotificationCenter.default.post(
            name: .daylightNotificationResponse,
            object: nil,
            userInfo: userInfo
        )
    }

    public func consumePendingResponse() -> [String: String]? {
        pendingResponses.withLock { responses in
            guard !responses.isEmpty else { return nil }
            return responses.removeFirst()
        }
    }
}
