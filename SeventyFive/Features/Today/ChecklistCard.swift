import SwiftUI
import SwiftData

/// The checklist for one day. Used for today and, via `DaySheet`, for yesterday.
struct ChecklistCard: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(PrefKey.waterUnit) private var waterUnitRaw = WaterUnit.localeDefault.rawValue

    let challenge: Challenge
    let entry: DailyEntry
    let onTakePhoto: () -> Void

    private var waterUnit: WaterUnit { WaterUnit(rawValue: waterUnitRaw) ?? .liters }

    var body: some View {
        let tasks = challenge.mode.tasks
        VStack(spacing: 0) {
            ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                row(for: task)
                if index < tasks.count - 1 {
                    Divider().overlay(Theme.line).padding(.leading, 64)
                }
            }
        }
        .card(padding: 6)
    }

    @ViewBuilder
    private func row(for task: TaskKind) -> some View {
        switch task {
        case .water:
            CounterRowView(
                task: task, label: "Water",
                current: entry.waterLiters,
                goal: challenge.waterGoalLiters,
                step: waterUnit.stepLiters,
                format: { waterUnit.format(liters: $0) },
                quickAdds: waterUnit.quickAdds.map { (label: $0.label, amount: $0.liters) },
                set: { value in
                    entry.waterLiters = min(max(0, value), 20)
                    sync(task, current: entry.waterLiters, goal: challenge.waterGoalLiters)
                }
            )
        case .reading(let goal, _):
            switch goal {
            case .pages(let pages):
                CounterRowView(
                    task: task, label: "Pages",
                    current: Double(entry.pagesRead), goal: Double(pages), step: 1,
                    format: { "\(Int($0)) pages" },
                    set: { value in
                        entry.pagesRead = min(max(0, Int(value)), 2000)
                        sync(task, current: Double(entry.pagesRead), goal: Double(pages))
                    }
                )
            case .minutes(let minutes):
                CounterRowView(
                    task: task, label: "Reading",
                    current: Double(entry.readingMinutes), goal: Double(minutes), step: 1,
                    format: { "\(Int($0)) min" },
                    set: { value in
                        entry.readingMinutes = min(max(0, Int(value)), 1440)
                        sync(task, current: Double(entry.readingMinutes), goal: Double(minutes))
                    }
                )
            }
        case .meditation(let minutes):
            CounterRowView(
                task: task, label: "Meditation",
                current: Double(entry.meditationMinutes), goal: Double(minutes), step: 1,
                format: { "\(Int($0)) min" },
                set: { value in
                    entry.meditationMinutes = min(max(0, Int(value)), 1440)
                    sync(task, current: Double(entry.meditationMinutes), goal: Double(minutes))
                }
            )
        case .progressPhoto:
            ChecklistRowView(
                task: task,
                isComplete: entry.isComplete(task),
                subtitle: entry.photos.isEmpty ? "Tap to open the camera" : "\(entry.photos.count) taken · tap to add another",
                action: onTakePhoto
            )
        case .workout where entry.isPlannedRestDay:
            // On a planned 75 Soft rest day the workout is excused, not pending.
            ChecklistRowView(task: task, isComplete: true, subtitle: "Rest day", isExcused: true) {}
                .disabled(true)
                .opacity(0.6)
        default:
            ChecklistRowView(task: task, isComplete: entry.isComplete(task)) {
                withAnimation(.snappy) { entry.toggle(task) }
                try? modelContext.save()
            }
        }
    }

    private func sync(_ task: TaskKind, current: Double, goal: Double) {
        // Floating-point water totals (8 oz steps) can land a hair under the goal.
        if current + 0.0005 >= goal {
            entry.markComplete(task)
        } else {
            entry.markIncomplete(task)
        }
        try? modelContext.save()
    }
}

/// A sheet for logging a day other than today — in practice, yesterday while it's still open.
struct DaySheet: View {
    @Environment(\.dismiss) private var dismiss
    let challenge: Challenge
    let entry: DailyEntry
    @State private var showCamera = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text("Log anything you finished on Day \(entry.dayNumber). It locks when today ends.")
                        .font(.footnote)
                        .foregroundStyle(Theme.dim)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ChecklistCard(challenge: challenge, entry: entry) { showCamera = true }
                }
                .padding(20)
            }
            .themedBackground(glow: entry.completionFraction)
            .navigationTitle("Day \(entry.dayNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                ProgressPhotoCaptureView(challenge: challenge, dailyEntry: entry)
            }
        }
    }
}
