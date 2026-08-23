import Foundation
import SwiftData

@Model
final class DailyEntry {
    var id: UUID
    var dayNumber: Int
    var date: Date
    var isPlannedRestDay: Bool
    var completedTaskIDs: Set<String>
    var waterLiters: Double
    var pagesRead: Int
    var notes: String

    var challenge: Challenge?

    @Relationship(deleteRule: .cascade, inverse: \ProgressPhoto.dailyEntry)
    var photos: [ProgressPhoto] = []

    init(dayNumber: Int, date: Date, isPlannedRestDay: Bool = false) {
        self.id = UUID()
        self.dayNumber = dayNumber
        self.date = date
        self.isPlannedRestDay = isPlannedRestDay
        self.completedTaskIDs = []
        self.waterLiters = 0
        self.pagesRead = 0
        self.notes = ""
    }

    func isComplete(_ task: TaskKind) -> Bool {
        completedTaskIDs.contains(task.id)
    }

    func toggle(_ task: TaskKind) {
        if completedTaskIDs.contains(task.id) {
            completedTaskIDs.remove(task.id)
        } else {
            completedTaskIDs.insert(task.id)
        }
    }

    func markComplete(_ task: TaskKind) {
        completedTaskIDs.insert(task.id)
    }

    var isFullyComplete: Bool {
        guard let mode = challenge?.mode else { return false }
        return mode.tasks.allSatisfy { completedTaskIDs.contains($0.id) }
    }

    var completionFraction: Double {
        guard let mode = challenge?.mode, !mode.tasks.isEmpty else { return 0 }
        let done = mode.tasks.filter { completedTaskIDs.contains($0.id) }.count
        return Double(done) / Double(mode.tasks.count)
    }
}
