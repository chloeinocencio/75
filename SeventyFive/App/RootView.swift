import SwiftUI
import SwiftData

enum AppTab: Hashable {
    case today, photos, compare, friends
}

struct RootView: View {
    @Query(filter: #Predicate<Challenge> { !$0.isArchived }, sort: \Challenge.startDate, order: .reverse)
    private var challenges: [Challenge]

    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var appLock: AppLock
    @State private var tab: AppTab = .today
    @State private var returningFromBackground = false

    var body: some View {
        ZStack {
            if let challenge = challenges.first {
                TabView(selection: $tab) {
                    TodayView(challenge: challenge, selectedTab: $tab)
                        .tabItem { Label("Today", systemImage: "checklist") }
                        .tag(AppTab.today)

                    PhotoTimelineView(challenge: challenge)
                        .tabItem { Label("Photos", systemImage: "photo.stack") }
                        .tag(AppTab.photos)

                    BeforeAfterCompareView(challenge: challenge)
                        .tabItem { Label("Compare", systemImage: "square.split.2x1") }
                        .tag(AppTab.compare)

                    FriendsView(challenge: challenge)
                        .tabItem { Label("Friends", systemImage: "person.2") }
                        .tag(AppTab.friends)
                }
            } else {
                OnboardingView()
            }

            // Covers the screen whenever the app isn't frontmost, so progress photos never
            // appear in the app switcher's snapshot — and stays up while locked.
            if scenePhase != .active || appLock.isLocked {
                PrivacyShield(isLocked: appLock.isLocked)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .animation(.easeOut(duration: 0.2), value: scenePhase)
        .animation(.easeOut(duration: 0.2), value: appLock.isLocked)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                appLock.lockIfEnabled()
                returningFromBackground = true
            case .active:
                // Prompt only on a real return from the background. The Face ID sheet itself
                // makes the scene inactive → active, so prompting on every `.active` would
                // re-open it forever after a cancel. The Unlock button covers retries.
                if returningFromBackground && appLock.isLocked {
                    Task { await appLock.unlock() }
                }
                returningFromBackground = false
            default:
                break
            }
        }
        .task {
            if appLock.isLocked { await appLock.unlock() }
        }
    }
}

private struct PrivacyShield: View {
    let isLocked: Bool
    @EnvironmentObject private var appLock: AppLock

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            AuraBackground(glow: 0.4).ignoresSafeArea()

            VStack(spacing: 18) {
                Text("75")
                    .font(.system(size: 64, weight: .heavy))
                    .foregroundStyle(Theme.accentText)
                if isLocked {
                    Text("Locked")
                        .font(.headline)
                        .foregroundStyle(Theme.dim)
                    Button {
                        Task { await appLock.unlock() }
                    } label: {
                        Label("Unlock with \(AppLock.biometryName)", systemImage: "lock.open.fill")
                    }
                    .buttonStyle(LimeButtonStyle(compact: true))
                }
            }
        }
    }
}
