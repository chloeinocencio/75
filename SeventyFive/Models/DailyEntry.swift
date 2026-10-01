import Foundation
import SwiftData

@Model
final class DailyEntry {
    var id: UUID
    var dayNumber: Int
    var date: Date
    /// Which run of the challenge this day belongs to. 75 Hard restarts bump this rather
    /// than deleting history, so earlier attempts (and their photos) survive.
    var attemptNumber: Int
    var isPlannedRestDay: Bool
    /// Stored as an Array rather than a Set: SwiftData's support for Set-typed attributes
    /// is less reliable than Array, and order is irrelevant here.
    var completedTaskIDs: [String]
    var waterLiters: Double
    var pagesRead: Int
    var readingMinutes: Int
    var meditationMinutes: Int
    var notes: String

    var challenge: Challenge?

    @Relationship(deleteRule: .cascade, inverse: \ProgressPhoto.dailyEntry)
    var photos: [ProgressPhoto] = []

    init(dayNumber: Int, date: Date, attemptNumber: Int = 1, isPlannedRestDay: Bool = false) {
        self.id = UUID()
        self.dayNumber = dayNumber
        self.date = date
        self.attemptNumber = attemptNumber
        self.isPlannedRestDay = isPlannedRestDay
        self.completedTaskIDs = []
        self.waterLiters = 0
        self.pagesRead = 0
        self.readingMinutes = 0
        self.meditationMinutes = 0
        self.notes = ""
    }

    func isComplete(_ task: TaskKind) -> Bool {
        completedTaskIDs.contains(task.id)
    }

    func toggle(_ task: TaskKind) {
        if completedTaskIDs.contains(task.id) {
            markIncomplete(task)
        } else {
            markComplete(task)
        }
    }

    func markComplete(_ task: TaskKind) {
        guard !completedTaskIDs.contains(task.id) else { return }
        completedTaskIDs.append(task.id)
    }

    func markIncomplete(_ task: TaskKind) {
        completedTaskIDs.removeAll { $0 == task.id }
    }

    /// The tasks that actually count toward today — a planned 75 Soft rest day excuses the
    /// workout but nothing else.
    var requiredTasks: [TaskKind] {
        guard let mode = challenge?.mode else { return [] }
        if mode.allowsWeeklyRestDay && isPlannedRestDay {
            return mode.tasks.filter { task in
                if case .workout = task { return false }
                return true
            }
        }
        return mode.tasks
    }

    var isFullyComplete: Bool {
        let tasks = requiredTasks
        guard !tasks.isEmpty else { return false }
        return tasks.allSatisfy { completedTaskIDs.contains($0.id) }
    }

    /// Measured against `requiredTasks` so the ring can still reach 100% on a rest day.
    var completionFraction: Double {
        let tasks = requiredTasks
        guard !tasks.isEmpty else { return 0 }
        let done = tasks.filter { completedTaskIDs.contains($0.id) }.count
        return Double(done) / Double(tasks.count)
    }
}
