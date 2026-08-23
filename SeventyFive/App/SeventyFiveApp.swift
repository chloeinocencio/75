import SwiftUI
import SwiftData

@main
struct SeventyFiveApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [Challenge.self, DailyEntry.self, ProgressPhoto.self, Friend.self])
    }
}
