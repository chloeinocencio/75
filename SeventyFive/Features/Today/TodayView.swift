import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    let challenge: Challenge

    @State private var showCamera = false
    @State private var showResetConfirm = false

    private var dailyEntry: DailyEntry {
        let dayNumber = challenge.currentDayNumber
        if let existing = challenge.entry(forDay: dayNumber) {
            return existing
        }
        let entry = DailyEntry(dayNumber: dayNumber, date: .now)
        entry.challenge = challenge
        challenge.days.append(entry)
        modelContext.insert(entry)
        try? modelContext.save()
        return entry
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header

                    if challenge.needsHardReset {
                        hardResetBanner
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(challenge.mode.tasks) { task in
                            row(for: task)
                            if task.id != challenge.mode.tasks.last?.id {
                                Divider()
                            }
                        }
                    }
                    .padding()
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))

                    if challenge.mode.photoCadence == .milestone {
                        milestonePhotoCard
                    }

                    if challenge.mode.allowsWeeklyRestDay {
                        restDayCard
                    }
                }
                .padding()
            }
            .navigationTitle(challenge.mode.rawValue)
            .fullScreenCover(isPresented: $showCamera) {
                ProgressPhotoCaptureView(challenge: challenge, dailyEntry: dailyEntry)
            }
            .alert("Restart at Day 1?", isPresented: $showResetConfirm) {
                Button("Restart", role: .destructive) {
                    challenge.restartFromDayOne(in: modelContext)
                    try? modelContext.save()
                }
                Button("Not yet", role: .cancel) {}
            } message: {
                Text("75 Hard requires starting over after a missed day. Your photos are kept.")
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(.secondary.opacity(0.15), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: dailyEntry.completionFraction)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut, value: dailyEntry.completionFraction)
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
            Text("75 Hard has no grace days — the rule is to restart at Day 1. Your progress photos stay saved.")
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
    private func row(for task: TaskKind) -> some View {
        switch task {
        case .water:
            counterRow(
                task: task,
                label: "Water",
                current: dailyEntry.waterLiters,
                goal: challenge.waterGoalLiters,
                step: 0.25,
                format: { "\($0.formatted(.number.precision(.fractionLength(0...1))))L" },
                set: { dailyEntry.waterLiters = max(0, $0) }
            )
        case .reading(let goal, _):
            switch goal {
            case .pages(let pages):
                counterRow(
                    task: task,
                    label: "Reading",
                    current: Double(dailyEntry.pagesRead),
                    goal: Double(pages),
                    step: 1,
                    format: { "\(Int($0)) pages" },
                    set: { dailyEntry.pagesRead = max(0, Int($0)) }
                )
            case .minutes(let minutes):
                counterRow(
                    task: task,
                    label: "Reading",
                    current: Double(dailyEntry.readingMinutes),
                    goal: Double(minutes),
                    step: 1,
                    format: { "\(Int($0)) min" },
                    set: { dailyEntry.readingMinutes = max(0, Int($0)) }
                )
            }
        case .meditation(let minutes):
            counterRow(
                task: task,
                label: "Meditation",
                current: Double(dailyEntry.meditationMinutes),
                goal: Double(minutes),
                step: 1,
                format: { "\(Int($0)) min" },
                set: { dailyEntry.meditationMinutes = max(0, Int($0)) }
            )
        case .progressPhoto:
            ChecklistRowView(task: task, isComplete: dailyEntry.isComplete(task)) {
                showCamera = true
            }
        default:
            ChecklistRowView(task: task, isComplete: dailyEntry.isComplete(task)) {
                dailyEntry.toggle(task)
                try? modelContext.save()
            }
        }
    }

    /// Shared numeric-goal row: water, pages, reading minutes, meditation minutes.
    private func counterRow(
        task: TaskKind,
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
                    .foregroundStyle(dailyEntry.isComplete(task) ? Color.accentColor : .secondary)
            }
            HStack(spacing: 12) {
                stepButton(systemImage: "minus") {
                    set(current - step)
                    syncCompletion(task: task, current: current - step, goal: goal)
                }
                ProgressView(value: min(current / max(goal, 0.001), 1))
                stepButton(systemImage: "plus") {
                    set(current + step)
                    syncCompletion(task: task, current: current + step, goal: goal)
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

    private func syncCompletion(task: TaskKind, current: Double, goal: Double) {
        if current >= goal {
            dailyEntry.markComplete(task)
        } else {
            dailyEntry.completedTaskIDs.remove(task.id)
        }
        try? modelContext.save()
    }

    /// Soft and Medium don't require a daily photo — this surfaces the Day 1 / Day 75
    /// milestones and otherwise offers an optional shot.
    private var milestonePhotoCard: some View {
        let day = challenge.currentDayNumber
        let isMilestone = challenge.isPhotoExpected(onDay: day)
        let hasPhotoToday = !dailyEntry.photos.isEmpty

        return VStack(alignment: .leading, spacing: 8) {
            Label(
                isMilestone ? "Day \(day) milestone photo" : "Optional progress photo",
                systemImage: hasPhotoToday ? "checkmark.circle.fill" : "camera.fill"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(hasPhotoToday ? Color.accentColor : .primary)

            Text(isMilestone
                 ? "\(challenge.mode.rawValue) calls for a photo on Day 1 and Day \(challenge.totalDays). This is one of them."
                 : "Not required today, but a weekly shot makes your before/after much better.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Group {
                if isMilestone && !hasPhotoToday {
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
            isMilestone && !hasPhotoToday ? Color.accentColor.opacity(0.10) : Color(.secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 16)
        )
    }

    private var restDayCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(
                get: { dailyEntry.isPlannedRestDay },
                set: { newValue in
                    dailyEntry.isPlannedRestDay = newValue
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
