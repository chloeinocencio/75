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

    /// Days belonging to the current attempt. Earlier attempts stay in `days` as history.
    var currentAttemptDays: [DailyEntry] {
        days.filter { $0.attemptNumber == attemptNumber }
    }

    var completedDayCount: Int {
        currentAttemptDays.filter(\.isFullyComplete).count
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

    /// Days that have elapsed in this attempt but were not fully completed. Drives Medium's
    /// 68-of-75 budget and Hard's reset rule.
    var missedDayCount: Int {
        let lastElapsed = currentDayNumber - 1
        guard lastElapsed >= 1 else { return 0 }
        return (1...lastElapsed).filter { dayNumber in
            guard let entry = entry(forDay: dayNumber) else { return true }
            return !entry.isFullyComplete
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
        let sorted = currentAttemptDays.sorted { $0.dayNumber > $1.dayNumber }
        var streak = 0
        for day in sorted {
            if day.isFullyComplete {
                streak += 1
            } else {
                break
            }
        }
        return streak
    }

    func entry(forDay dayNumber: Int) -> DailyEntry? {
        days.first { $0.dayNumber == dayNumber && $0.attemptNumber == attemptNumber }
    }

    /// A photo is *required* today only under 75 Hard. Soft and Medium ask for one on the
    /// first and last day, and treat everything in between as optional.
    func isPhotoExpected(onDay dayNumber: Int) -> Bool {
        switch mode.photoCadence {
        case .daily: return true
        case .milestone: return dayNumber == 1 || dayNumber == totalDays
        }
    }

    /// Restarts a failed 75 Hard run at Day 1.
    ///
    /// Nothing is deleted: bumping `attemptNumber` scopes the new run's days away from the
    /// old ones. Deleting the old `DailyEntry` rows would cascade into their `ProgressPhoto`
    /// rows, silently losing every photo the user had taken while leaving orphaned JPEGs on
    /// disk — so history is retained instead.
    func restartFromDayOne() {
        startDate = Calendar.current.startOfDay(for: .now)
        attemptNumber += 1
    }

    /// Most recent photo of a given pose, used as the ghost-overlay alignment guide so every
    /// photo is framed the same way. Looks across attempts on purpose: after a 75 Hard
    /// restart you still want to line up against your most recent shot.
    func lastPhoto(before dayNumber: Int, pose: PhotoPose) -> ProgressPhoto? {
        days
            .filter { $0.attemptNumber < attemptNumber || $0.dayNumber < dayNumber }
            .flatMap(\.photos)
            .filter { $0.pose == pose }
            .max { $0.date < $1.date }
    }
}
