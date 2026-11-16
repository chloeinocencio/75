import SwiftUI
import SwiftData

@main
struct SeventyFiveApp: App {
    @StateObject private var social = SocialService()
    @StateObject private var appLock = AppLock()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(social)
                .environmentObject(appLock)
                .tint(Theme.accentText)
        }
        .modelContainer(for: [Challenge.self, DailyEntry.self, ProgressPhoto.self])
    }
}
