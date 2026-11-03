import SwiftUI
import UserNotifications

@main struct MyApp: App {
    init() {
        UNUserNotificationCenter.current().delegate = DaylightNotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
