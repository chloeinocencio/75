import SwiftUI
import SwiftData
import Combine

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var social: SocialService
    @AppStorage(PrefKey.remindersEnabled) private var remindersEnabled = false
    @AppStorage(PrefKey.reminderMinutes) private var reminderMinutes = 20 * 60

    let challenge: Challenge
    @Binding var selectedTab: AppTab

    @State private var cameraEntry: DailyEntry?
    @State private var sheetEntry: DailyEntry?
    @State private var showResetConfirm = false
    @State private var showNewChallengeConfirm = false
    @State private var showSettings = false
    @State private var bloom = false
    @State private var ringShown = false

    /// Fires at local midnight, and on a time-zone or daylight-saving change — the three
    /// ways "today" can become a different day while the app is sitting open. Delivered on
    /// the main queue so the SwiftData writes below stay on the main actor.
    private var timeChanges: AnyPublisher<Void, Never> {
        NotificationCenter.default
            .publisher(for: UIApplication.significantTimeChangeNotification)
            .map { _ in () }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    /// Today's record, or nil until `ensureEntry` has created it.
    ///
    /// Deliberately read-only: creating the entry lazily from inside `body` would mutate
    /// SwiftData mid-render, which SwiftUI treats as a state change and re-renders for — a
    /// feedback loop. Creation happens in `.task` and on rollover instead.
    private var todayEntry: DailyEntry? {
        challenge.entry(forDay: challenge.currentDayNumber)
    }

    @discardableResult
    @MainActor
    private func ensureEntry(day dayNumber: Int) -> DailyEntry {
        if let existing = challenge.entry(forDay: dayNumber) { return existing }
        let calendar = Challenge.dayCalendar
        let offset = dayNumber - challenge.calendarDayNumber
        let date = calendar.date(byAdding: .day, value: offset, to: .now) ?? .now
        let entry = DailyEntry(dayNumber: dayNumber, date: date, attemptNumber: challenge.attemptNumber)
        modelContext.insert(entry)
        entry.challenge = challenge
        try? modelContext.save()
        return entry
    }

    /// Catches up after midnight, a flight, or a daylight-saving change: records the day
    /// reached and opens a record for it.
    @MainActor
    private func rollOverIfNeeded() {
        challenge.advanceDayIfNeeded()
        if !challenge.isPastFinalDay {
            ensureEntry(day: challenge.currentDayNumber)
        }
        try? modelContext.save()
        syncOutside()
    }

    /// Keeps reminders and the friends snapshot in step with the checklist.
    private func syncOutside() {
        let fraction = todayEntry?.completionFraction ?? 0
        let done = todayEntry?.isFullyComplete ?? false
        if remindersEnabled && challenge.outcome == .inProgress {
            ReminderService.reschedule(
                minutesAfterMidnight: reminderMinutes,
                todayComplete: done,
                mode: challenge.mode,
                currentDay: challenge.currentDayNumber,
                totalDays: challenge.totalDays
            )
        }
        let snapshot = ProgressSnapshot(
            tier: challenge.mode.rawValue,
            day: challenge.currentDayNumber,
            totalDays: challenge.totalDays,
            streak: challenge.currentStreak,
            todayFraction: fraction
        )
        Task { await social.publish(snapshot) }
    }

    var body: some View {
        let fraction = todayEntry?.completionFraction ?? (challenge.outcome == .inProgress ? 0 : 1)

        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    hero(fraction: fraction)
                    statsRow

                    if challenge.outcome != .inProgress {
                        finishCard
                    }

                    if challenge.needsHardReset && challenge.outcome == .inProgress {
                        hardResetBanner
                    } else if challenge.isOverMissBudget && challenge.outcome == .inProgress {
                        overBudgetBanner
                    }

                    if let yesterday = challenge.yesterdayDayNumber,
                       case .open = challenge.status(ofDay: yesterday) {
                        yesterdayCard(day: yesterday)
                    }

                    if let entry = todayEntry, !challenge.isPastFinalDay {
                        VStack(spacing: 10) {
                            SectionLabel(text: "Today's checklist")
                            ChecklistCard(challenge: challenge, entry: entry) { cameraEntry = entry }
                        }

                        if challenge.mode.photoCadence == .milestone {
                            milestonePhotoCard(for: entry)
                        }
                        if challenge.mode.allowsWeeklyRestDay {
                            restDayCard(for: entry)
                        }
                    } else if !challenge.isPastFinalDay {
                        ProgressView().padding(.top, 40)
                    }

                    MosaicCard(challenge: challenge) { day in
                        sheetEntry = ensureEntry(day: day)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .themedBackground(glow: fraction, bloom: bloom)
            .navigationTitle(challenge.mode.rawValue)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .task { rollOverIfNeeded() }
            .onReceive(timeChanges) { rollOverIfNeeded() }
            .onChange(of: scenePhase) { _, phase in
                // Covers the app being backgrounded overnight, where no notification arrives.
                if phase == .active { rollOverIfNeeded() }
            }
            .onChange(of: todayEntry?.completionFraction ?? 0) { _, _ in syncOutside() }
            .onChange(of: todayEntry?.isFullyComplete ?? false) { old, new in
                if !old && new { celebrate() }
            }
            .sensoryFeedback(.success, trigger: bloom) { _, new in new }
            .fullScreenCover(item: $cameraEntry) { entry in
                ProgressPhotoCaptureView(challenge: challenge, dailyEntry: entry)
            }
            .sheet(item: $sheetEntry) { entry in
                DaySheet(challenge: challenge, entry: entry)
                    .presentationDetents([.large])
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(challenge: challenge)
            }
            .alert("Restart at Day 1?", isPresented: $showResetConfirm) {
                Button("Restart", role: .destructive) {
                    challenge.restartFromDayOne()
                    try? modelContext.save()
                    ensureEntry(day: 1)
                    syncOutside()
                }
                Button("Not yet", role: .cancel) {}
            } message: {
                Text("75 Hard requires starting over after a missed day. Your previous days and photos stay in your history.")
            }
            .confirmationDialog("Start a new challenge?", isPresented: $showNewChallengeConfirm, titleVisibility: .visible) {
                Button("Start a new challenge") { archiveAndRestart() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This challenge and its photos stay saved on your iPhone.")
            }
        }
    }

    // MARK: - Hero

    private func hero(fraction: Double) -> some View {
        HStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(Theme.surface2, lineWidth: 12)
                Circle()
                    .trim(from: 0, to: ringShown ? fraction : 0)
                    .stroke(Theme.lime, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.95), value: fraction)
                    .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.95), value: ringShown)
                VStack(spacing: -2) {
                    Text("\(challenge.currentDayNumber)")
                        .font(.system(size: 46, weight: .heavy))
                        .tracking(-1.5)
                        .foregroundStyle(Theme.ink)
                        .contentTransition(.numericText(value: Double(challenge.currentDayNumber)))
                    Text("of \(challenge.totalDays)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.dim)
                }
            }
            .frame(width: 136, height: 136)
            .scaleEffect(bloom ? 1.055 : 1)
            .animation(.spring(response: 0.5, dampingFraction: 0.55), value: bloom)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Day \(challenge.currentDayNumber) of \(challenge.totalDays)")
            .accessibilityValue("Today \(Int(fraction * 100)) percent done")

            VStack(alignment: .leading, spacing: 6) {
                Text(headline(fraction: fraction))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(Date.now.formatted(.dateTime.weekday(.wide).month().day()))
                    .font(.subheadline)
                    .foregroundStyle(Theme.dim)
                if challenge.attemptNumber > 1 {
                    Text("Attempt \(challenge.attemptNumber)")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.surface2, in: Capsule())
                        .foregroundStyle(Theme.ink)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
        .onAppear { ringShown = true }
    }

    private func headline(fraction: Double) -> String {
        if challenge.outcome == .completed { return "You did it." }
        if challenge.isPastFinalDay { return "Challenge over." }
        let remaining = todayEntry.map { entry in
            entry.requiredTasks.filter { !entry.isComplete($0) }.count
        } ?? challenge.mode.tasks.count
        switch remaining {
        case 0: return "Day done. 🎉"
        case 1: return "One task left."
        default: return fraction == 0 ? "Let's start the day." : "\(remaining) tasks left."
        }
    }

    private var statsRow: some View {
        HStack(spacing: 10) {
            stat(value: "\(challenge.currentStreak)", label: "Streak", icon: "flame.fill")
            stat(value: "\(challenge.completedDayCount)", label: "Days done", icon: "checkmark.seal.fill")
            if let remaining = challenge.missesRemaining {
                stat(value: "\(remaining)", label: "Misses left", icon: "heart.fill")
            } else {
                stat(value: "\(challenge.bestStreak)", label: "Best streak", icon: "trophy.fill")
            }
        }
    }

    private func stat(value: String, label: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.dim)
            Text(value)
                .font(.title2.weight(.heavy))
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText())
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.dim)
        }
        .card(padding: 12)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Banners

    /// Inverted ink-on-cream rather than red, matching the web build's alerts.
    private var hardResetBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("A day was missed", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
            Text("75 Hard has no grace days — the rule is to restart at Day 1. Your history and photos are kept.")
                .font(.subheadline)
                .opacity(0.8)
            Button("Restart at Day 1") { showResetConfirm = true }
                .buttonStyle(LimeButtonStyle(compact: true))
        }
        .foregroundStyle(Theme.bg)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.ink, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    private var overBudgetBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Over the 7-miss allowance", systemImage: "heart.slash.fill")
                .font(.headline)
            Text("75 Medium finishes at 68 of 75 days. You can keep going for the habit — or start fresh.")
                .font(.subheadline)
                .opacity(0.8)
            Button("Start fresh") { showNewChallengeConfirm = true }
                .buttonStyle(LimeButtonStyle(compact: true))
        }
        .foregroundStyle(Theme.bg)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.ink, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    private func yesterdayCard(day: Int) -> some View {
        Button {
            sheetEntry = ensureEntry(day: day)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.title3.weight(.semibold))
                    .frame(width: 40, height: 40)
                    .background(Theme.limeSoft, in: Circle())
                    .foregroundStyle(Theme.ink)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Day \(day) isn't finished")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text("Forgot to log something? You can until today ends.")
                        .font(.caption)
                        .foregroundStyle(Theme.dim)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.dim)
            }
            .card()
        }
        .buttonStyle(.plain)
    }

    private var finishCard: some View {
        let completed = challenge.outcome == .completed
        return VStack(alignment: .leading, spacing: 12) {
            Text(completed ? "\(challenge.mode.rawValue) complete" : "\(challenge.mode.rawValue) is over")
                .font(.title2.weight(.heavy))
                .foregroundStyle(Theme.limeInk)
            Text(completed
                 ? "\(challenge.completedDayCount) days done, best streak \(challenge.bestStreak). That's the whole thing."
                 : "You finished \(challenge.completedDayCount) of \(challenge.totalDays) days. Every one of them counts.")
                .font(.subheadline)
                .foregroundStyle(Theme.limeInk.opacity(0.8))
            HStack(spacing: 10) {
                Button("See before & after") { selectedTab = .compare }
                    .buttonStyle(QuietButtonStyle())
                Button("New challenge") { showNewChallengeConfirm = true }
                    .buttonStyle(QuietButtonStyle())
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.lime, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    // MARK: - Photo & rest day

    /// Soft and Medium don't require a daily photo — this surfaces the Day 1 / Day 75
    /// milestones and otherwise offers an optional shot.
    private func milestonePhotoCard(for entry: DailyEntry) -> some View {
        let day = challenge.currentDayNumber
        let isMilestone = challenge.isPhotoExpected(onDay: day)
        let hasPhotoToday = !entry.photos.isEmpty
        let highlight = isMilestone && !hasPhotoToday

        return HStack(spacing: 14) {
            Image(systemName: hasPhotoToday ? "checkmark" : "camera.fill")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 40, height: 40)
                .foregroundStyle(highlight || hasPhotoToday ? Theme.limeInk : Theme.ink)
                .background(highlight || hasPhotoToday ? Theme.lime : Theme.surface2, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(isMilestone ? "Day \(day) milestone photo" : "Progress photo")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text(isMilestone
                     ? "\(challenge.mode.rawValue) asks for a photo on Day 1 and Day \(challenge.totalDays)."
                     : "Optional today — a weekly shot makes your before & after much better.")
                    .font(.caption)
                    .foregroundStyle(Theme.dim)
            }
            Spacer(minLength: 4)
            Button(hasPhotoToday ? "Another" : "Take") { cameraEntry = entry }
                .buttonStyle(LimeButtonStyle(compact: true))
        }
        .card()
    }

    private func restDayCard(for entry: DailyEntry) -> some View {
        // One rest day per rolling 7 days: blocked if any of the previous six days used it.
        let day = entry.dayNumber
        let usedRecently = (max(1, day - 6)..<day).contains { challenge.entry(forDay: $0)?.isPlannedRestDay == true }
        let locked = usedRecently && !entry.isPlannedRestDay

        return VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(
                get: { entry.isPlannedRestDay },
                set: { newValue in
                    entry.isPlannedRestDay = newValue
                    try? modelContext.save()
                }
            )) {
                Label("Use my weekly rest day", systemImage: "bed.double.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
            }
            .tint(Theme.lime)
            .disabled(locked)
            Text(locked
                 ? "You've used your rest day this week. The next one opens on Day \(nextRestDay(after: day))."
                 : "75 Soft allows one active-recovery day a week in place of the workout. Everything else still counts.")
                .font(.caption)
                .foregroundStyle(Theme.dim)
        }
        .card()
    }

    private func nextRestDay(after day: Int) -> Int {
        let lastUsed = (max(1, day - 6)..<day).last { challenge.entry(forDay: $0)?.isPlannedRestDay == true } ?? day
        return lastUsed + 7
    }

    // MARK: - Actions

    private func celebrate() {
        bloom = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { bloom = false }
    }

    private func archiveAndRestart() {
        challenge.isArchived = true
        try? modelContext.save()
        ReminderService.cancelAll()
    }
}
