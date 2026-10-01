import SwiftUI
import SwiftData
import Combine

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    let challenge: Challenge

    @State private var showCamera = false
    @State private var showResetConfirm = false

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

    /// Today's record, or nil until `ensureTodayEntry()` has created it.
    ///
    /// This is deliberately read-only: creating the entry lazily from inside `body` would
    /// mutate SwiftData mid-render, which SwiftUI treats as a state change and re-renders
    /// for — a feedback loop. Creation happens once in `.task` instead.
    private var dailyEntry: DailyEntry? {
        challenge.entry(forDay: challenge.currentDayNumber)
    }

    @MainActor
    private func ensureTodayEntry() {
        let dayNumber = challenge.currentDayNumber
        guard challenge.entry(forDay: dayNumber) == nil else { return }
        let entry = DailyEntry(dayNumber: dayNumber, date: .now, attemptNumber: challenge.attemptNumber)
        modelContext.insert(entry)
        entry.challenge = challenge
        try? modelContext.save()
    }

    /// Catches up after midnight, a flight, or a daylight-saving change: records the day
    /// reached and opens a record for it.
    @MainActor
    private func rollOverIfNeeded() {
        challenge.advanceDayIfNeeded()
        ensureTodayEntry()
        try? modelContext.save()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let entry = dailyEntry {
                    content(for: entry)
                } else {
                    ProgressView().padding(.top, 80)
                }
            }
            .navigationTitle(challenge.mode.rawValue)
            .task { rollOverIfNeeded() }
            .onReceive(timeChanges) { rollOverIfNeeded() }
            .onChange(of: scenePhase) { _, phase in
                // Covers the app being backgrounded overnight, where no notification arrives.
                if phase == .active { rollOverIfNeeded() }
            }
            .fullScreenCover(isPresented: $showCamera) {
                if let entry = dailyEntry {
                    ProgressPhotoCaptureView(challenge: challenge, dailyEntry: entry)
                }
            }
            .alert("Restart at Day 1?", isPresented: $showResetConfirm) {
                Button("Restart", role: .destructive) {
                    challenge.restartFromDayOne()
                    try? modelContext.save()
                    ensureTodayEntry()
                }
                Button("Not yet", role: .cancel) {}
            } message: {
                Text("75 Hard requires starting over after a missed day. Your previous days and photos stay in your history.")
            }
        }
    }

    private func content(for entry: DailyEntry) -> some View {
        VStack(spacing: 20) {
            header(for: entry)

            if challenge.needsHardReset {
                hardResetBanner
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(challenge.mode.tasks) { task in
                    row(for: task, entry: entry)
                    if task.id != challenge.mode.tasks.last?.id {
                        Divider()
                    }
                }
            }
            .padding()
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))

            if challenge.mode.photoCadence == .milestone {
                milestonePhotoCard(for: entry)
            }

            if challenge.mode.allowsWeeklyRestDay {
                restDayCard(for: entry)
            }
        }
        .padding()
    }

    private func header(for entry: DailyEntry) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(.secondary.opacity(0.15), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: entry.completionFraction)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut, value: entry.completionFraction)
                VStack {
                    Text("Day \(challenge.currentDayNumber)")
                        .font(.title2.bold())
                    Text("of \(challenge.totalDays)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 140, height: 140)

            HStack(spacing: 20) {
                statPill(value: "\(challenge.currentStreak)", label: "Streak", icon: "flame.fill")
                statPill(value: "\(challenge.completedDayCount)", label: "Completed", icon: "checkmark.seal.fill")
                if let remaining = challenge.missesRemaining {
                    statPill(value: "\(remaining)", label: "Misses left", icon: "heart.slash")
                } else {
                    statPill(value: "\(Int(challenge.progressFraction * 100))%", label: "Overall", icon: "chart.bar.fill")
                }
            }

            if challenge.attemptNumber > 1 {
                Text("Attempt \(challenge.attemptNumber)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 8)
    }

    private func statPill(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 2) {
            Label(value, systemImage: icon)
                .font(.subheadline.weight(.semibold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var hardResetBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("You missed a day", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            Text("75 Hard has no grace days — the rule is to restart at Day 1. Your history is kept.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Restart at Day 1") { showResetConfirm = true }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.small)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func row(for task: TaskKind, entry: DailyEntry) -> some View {
        switch task {
        case .water:
            counterRow(
                task: task, entry: entry, label: "Water",
                current: entry.waterLiters,
                goal: challenge.waterGoalLiters,
                step: 0.25,
                format: { "\($0.formatted(.number.precision(.fractionLength(0...1))))L" },
                set: { entry.waterLiters = max(0, $0) }
            )
        case .reading(let goal, _):
            switch goal {
            case .pages(let pages):
                counterRow(
                    task: task, entry: entry, label: "Reading",
                    current: Double(entry.pagesRead),
                    goal: Double(pages),
                    step: 1,
                    format: { "\(Int($0)) pages" },
                    set: { entry.pagesRead = max(0, Int($0)) }
                )
            case .minutes(let minutes):
                counterRow(
                    task: task, entry: entry, label: "Reading",
                    current: Double(entry.readingMinutes),
                    goal: Double(minutes),
                    step: 1,
                    format: { "\(Int($0)) min" },
                    set: { entry.readingMinutes = max(0, Int($0)) }
                )
            }
        case .meditation(let minutes):
            counterRow(
                task: task, entry: entry, label: "Meditation",
                current: Double(entry.meditationMinutes),
                goal: Double(minutes),
                step: 1,
                format: { "\(Int($0)) min" },
                set: { entry.meditationMinutes = max(0, Int($0)) }
            )
        case .progressPhoto:
            ChecklistRowView(task: task, isComplete: entry.isComplete(task)) {
                showCamera = true
            }
        case .workout where entry.isPlannedRestDay:
            // On a planned 75 Soft rest day the workout is excused, not pending.
            ChecklistRowView(task: task, isComplete: true) {}
                .disabled(true)
                .opacity(0.5)
        default:
            ChecklistRowView(task: task, isComplete: entry.isComplete(task)) {
                entry.toggle(task)
                try? modelContext.save()
            }
        }
    }

    /// Shared numeric-goal row: water, pages, reading minutes, meditation minutes.
    private func counterRow(
        task: TaskKind,
        entry: DailyEntry,
        label: String,
        current: Double,
        goal: Double,
        step: Double,
        format: @escaping (Double) -> String,
        set: @escaping (Double) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(label, systemImage: task.systemImage).font(.body.weight(.medium))
                Spacer()
                Text("\(format(current)) / \(format(goal))")
                    .font(.subheadline)
                    .foregroundStyle(entry.isComplete(task) ? Color.accentColor : Color.secondary)
            }
            HStack(spacing: 12) {
                stepButton(systemImage: "minus") {
                    let next = current - step
                    set(next)
                    syncCompletion(task: task, entry: entry, current: next, goal: goal)
                }
                ProgressView(value: min(current / max(goal, 0.001), 1))
                stepButton(systemImage: "plus") {
                    let next = current + step
                    set(next)
                    syncCompletion(task: task, entry: entry, current: next, goal: goal)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func stepButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 30, height: 30)
                .background(.secondary.opacity(0.12), in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func syncCompletion(task: TaskKind, entry: DailyEntry, current: Double, goal: Double) {
        if current >= goal {
            entry.markComplete(task)
        } else {
            entry.markIncomplete(task)
        }
        try? modelContext.save()
    }

    /// Soft and Medium don't require a daily photo — this surfaces the Day 1 / Day 75
    /// milestones and otherwise offers an optional shot.
    private func milestonePhotoCard(for entry: DailyEntry) -> some View {
        let day = challenge.currentDayNumber
        let isMilestone = challenge.isPhotoExpected(onDay: day)
        let hasPhotoToday = !entry.photos.isEmpty
        let highlight = isMilestone && !hasPhotoToday

        return VStack(alignment: .leading, spacing: 8) {
            Label(
                isMilestone ? "Day \(day) milestone photo" : "Optional progress photo",
                systemImage: hasPhotoToday ? "checkmark.circle.fill" : "camera.fill"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(hasPhotoToday ? Color.accentColor : Color.primary)

            Text(isMilestone
                 ? "\(challenge.mode.rawValue) calls for a photo on Day 1 and Day \(challenge.totalDays). This is one of them."
                 : "Not required today, but a weekly shot makes your before/after much better.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Group {
                if highlight {
                    Button("Take Photo") { showCamera = true }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button(hasPhotoToday ? "Take Another" : "Take Photo") { showCamera = true }
                        .buttonStyle(.bordered)
                }
            }
            .controlSize(.small)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            highlight ? Color.accentColor.opacity(0.10) : Color(.secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 16)
        )
    }

    private func restDayCard(for entry: DailyEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(
                get: { entry.isPlannedRestDay },
                set: { newValue in
                    entry.isPlannedRestDay = newValue
                    try? modelContext.save()
                }
            )) {
                Label("Use my weekly rest day", systemImage: "bed.double.fill")
                    .font(.subheadline.weight(.medium))
            }
            Text("75 Soft allows one active-recovery day per week in place of the workout. Everything else still counts.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }
}
