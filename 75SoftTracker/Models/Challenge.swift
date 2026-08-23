import Foundation
import SwiftData

@Model
final class Challenge {
    var id: UUID
    var modeRaw: String
    var startDate: Date
    var totalDays: Int
    var shareProgressWithFriends: Bool

    @Relationship(deleteRule: .cascade, inverse: \DailyEntry.challenge)
    var days: [DailyEntry] = []

    init(mode: ChallengeMode, startDate: Date = .now, totalDays: Int = 75, shareProgressWithFriends: Bool = false) {
        self.id = UUID()
        self.modeRaw = mode.rawValue
        self.startDate = Calendar.current.startOfDay(for: startDate)
        self.totalDays = totalDays
        self.shareProgressWithFriends = shareProgressWithFriends
    }

    var mode: ChallengeMode {
        get { ChallengeMode(rawValue: modeRaw) ?? .soft }
        set { modeRaw = newValue.rawValue }
    }

    var currentDayNumber: Int {
        let elapsed = Calendar.current.dateComponents([.day], from: startDate, to: Calendar.current.startOfDay(for: .now)).day ?? 0
        return min(max(elapsed + 1, 1), totalDays)
    }

    var completedDayCount: Int {
        days.filter(\.isFullyComplete).count
    }

    var progressFraction: Double {
        guard totalDays > 0 else { return 0 }
        return Double(completedDayCount) / Double(totalDays)
    }

    /// Longest unbroken streak of fully-completed days, ending today or the last completed day.
    var currentStreak: Int {
        let sorted = days.sorted { $0.dayNumber > $1.dayNumber }
        var streak = 0
        for day in sorted {
            if day.isFullyComplete || (mode.allowsWeeklyRestDay && day.isPlannedRestDay) {
                streak += 1
            } else {
                break
            }
        }
        return streak
    }

    func entry(forDay dayNumber: Int) -> DailyEntry? {
        days.first { $0.dayNumber == dayNumber }
    }

    /// Most recent photo of a given pose taken before `dayNumber`, used as the ghost-overlay
    /// alignment guide so every day's photo is framed the same way.
    func lastPhoto(before dayNumber: Int, pose: PhotoPose) -> ProgressPhoto? {
        days
            .filter { $0.dayNumber < dayNumber }
            .sorted { $0.dayNumber > $1.dayNumber }
            .compactMap { day in day.photos.first { $0.pose == pose } }
            .first
    }
}
