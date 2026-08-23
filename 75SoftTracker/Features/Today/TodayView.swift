import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    let challenge: Challenge

    @State private var showCamera = false
    @State private var showRestDayConfirm = false

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
                statPill(value: Int(challenge.progressFraction * 100).description + "%", label: "Overall", icon: "chart.bar.fill")
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

    @ViewBuilder
    private func row(for task: TaskKind) -> some View {
        switch task {
        case .water(let goalLiters):
            waterRow(goalLiters: goalLiters)
        case .reading(let goalPages):
            readingRow(goalPages: goalPages)
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

    private func waterRow(goalLiters: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Water", systemImage: "drop.fill").font(.body.weight(.medium))
                Spacer()
                Text("\(dailyEntry.waterLiters.formatted(.number.precision(.fractionLength(0...1))))L / \(goalLiters.formatted(.number.precision(.fractionLength(0...1))))L")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                stepButton(systemImage: "minus") {
                    dailyEntry.waterLiters = max(0, dailyEntry.waterLiters - 0.25)
                    syncWaterCompletion(goal: goalLiters)
                }
                ProgressView(value: min(dailyEntry.waterLiters / goalLiters, 1))
                stepButton(systemImage: "plus") {
                    dailyEntry.waterLiters += 0.25
                    syncWaterCompletion(goal: goalLiters)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func readingRow(goalPages: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Reading", systemImage: "book.fill").font(.body.weight(.medium))
                Spacer()
                Text("\(dailyEntry.pagesRead) / \(goalPages) pages")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                stepButton(systemImage: "minus") {
                    dailyEntry.pagesRead = max(0, dailyEntry.pagesRead - 1)
                    syncReadingCompletion(goal: goalPages)
                }
                ProgressView(value: min(Double(dailyEntry.pagesRead) / Double(goalPages), 1))
                stepButton(systemImage: "plus") {
                    dailyEntry.pagesRead += 1
                    syncReadingCompletion(goal: goalPages)
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

    private func syncWaterCompletion(goal: Double) {
        if dailyEntry.waterLiters >= goal {
            dailyEntry.markComplete(.water(liters: goal))
        }
        try? modelContext.save()
    }

    private func syncReadingCompletion(goal: Int) {
        if dailyEntry.pagesRead >= goal {
            dailyEntry.markComplete(.reading(pages: goal))
        }
        try? modelContext.save()
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
            Text("75 Soft allows one active-recovery day per week in place of the workout.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }
}
