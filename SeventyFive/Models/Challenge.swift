import Foundation
import SwiftData

@Model
final class Challenge {
    var id: UUID
    var modeRaw: String
    var startDate: Date
    var totalDays: Int
    var shareProgressWithFriends: Bool
    /// Only set for tiers that scale water to body weight (75 Medium).
    var bodyWeightPounds: Double?
    /// Incremented each time a 75 Hard run resets, so the user keeps a record of attempts.
    var attemptNumber: Int

    @Relationship(deleteRule: .cascade, inverse: \DailyEntry.challenge)
    var days: [DailyEntry] = []

    init(mode: ChallengeMode, startDate: Date = .now, totalDays: Int = 75, bodyWeightPounds: Double? = nil) {
        self.id = UUID()
        self.modeRaw = mode.rawValue
        self.startDate = Calendar.current.startOfDay(for: startDate)
        self.totalDays = totalDays
        self.shareProgressWithFriends = false
        self.bodyWeightPounds = bodyWeightPounds
        self.attemptNumber = 1
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

    var waterGoalLiters: Double {
        guard let task = mode.tasks.first(where: { if case .water = $0 { return true }; return false }),
              case .water(let goal) = task else { return 3.0 }
        return goal.resolvedLiters(bodyWeightPounds: bodyWeightPounds)
    }

    /// Days that have elapsed but were not fully completed. Drives Medium's 68-of-75 budget
    /// and Hard's reset rule.
    var missedDayCount: Int {
        let lastElapsed = currentDayNumber - 1
        guard lastElapsed >= 1 else { return 0 }
        return (1...lastElapsed).filter { dayNumber in
            guard let entry = entry(forDay: dayNumber) else { return true }
            return !entry.isFullyComplete && !(mode.allowsWeeklyRestDay && entry.isPlannedRestDay)
        }.count
    }

    /// Remaining grace under 75 Medium's allowance; nil where the concept doesn't apply.
    var missesRemaining: Int? {
        guard case .allowedMisses(let budget) = mode.failurePolicy else { return nil }
        return max(0, budget - missedDayCount)
    }

    /// True when a 75 Hard run has broken its own rule and owes the user a restart.
    var needsHardReset: Bool {
        mode.failurePolicy == .restartFromDayOne && missedDayCount > 0
    }

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

    /// A photo is *required* today only under 75 Hard. Soft and Medium ask for one on the
    /// first and last day, and treat everything in between as optional.
    func isPhotoExpected(onDay dayNumber: Int) -> Bool {
        switch mode.photoCadence {
        case .daily: return true
        case .milestone: return dayNumber == 1 || dayNumber == totalDays
        }
    }

    /// Restarts a failed 75 Hard run at Day 1, preserving photos taken so far by leaving
    /// their files on disk — only the day records are cleared.
    func restartFromDayOne(in context: ModelContext) {
        for day in days {
            context.delete(day)
        }
        days.removeAll()
        startDate = Calendar.current.startOfDay(for: .now)
        attemptNumber += 1
    }

    /// Most recent photo of a given pose taken before `dayNumber`, used as the ghost-overlay
    /// alignment guide so every photo is framed the same way.
    func lastPhoto(before dayNumber: Int, pose: PhotoPose) -> ProgressPhoto? {
        days
            .filter { $0.dayNumber < dayNumber }
            .sorted { $0.dayNumber > $1.dayNumber }
            .compactMap { day in day.photos.first { $0.pose == pose } }
            .first
    }
}
