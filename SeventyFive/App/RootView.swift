import SwiftUI
import SwiftData

struct RootView: View {
    @Query(sort: \Challenge.startDate, order: .reverse) private var challenges: [Challenge]

    var body: some View {
        if let challenge = challenges.first {
            TabView {
                TodayView(challenge: challenge)
                    .tabItem { Label("Today", systemImage: "checklist") }

                PhotoTimelineView(challenge: challenge)
                    .tabItem { Label("Photos", systemImage: "photo.stack") }

                BeforeAfterCompareView(challenge: challenge)
                    .tabItem { Label("Compare", systemImage: "square.split.2x1") }

                FriendsView(challenge: challenge)
                    .tabItem { Label("Friends", systemImage: "person.2") }
            }
        } else {
            OnboardingView()
        }
    }
}
