import Foundation
import SwiftData

@Model
final class Challenge {
    var id: UUID
    var modeRaw: String
    /// The instant the challenge began. Kept for sorting and display only — never for
    /// day arithmetic, because an instant re-read in another time zone is no longer
    /// that zone's midnight.
    var startDate: Date
    /// Day 1 as a *civil* date (Gregorian year/month/day, no time, no zone). This is the
    /// anchor all day counting uses, so flying between time zones cannot shift it.
    var startYear: Int = 1970
    var startMonth: Int = 1
    var startDay: Int = 1
    /// The furthest day the user has actually reached. Crossing the date line westward
    /// repeats a local calendar date; a day already lived shouldn't come back, so the
    /// count is clamped to never regress.
    var highestDayReached: Int = 1
    var totalDays: Int
    var shareProgressWithFriends: Bool
    /// Only set for tiers that scale water to body weight (75 Medium).
    var bodyWeightPounds: Double?
    /// Incremented each time a 75 Hard run resets, so the user keeps a record of attempts.
    var attemptNumber: Int

    @Relationship(deleteRule: .cascade, inverse: \DailyEntry.challenge)
    var days: [DailyEntry] = []

    init(mode: ChallengeMode, startDate: Date = .now, totalDays: Int = 75, bodyWeightPounds: Double? = nil) {
        let calendar = Self.dayCalendar
        let civil = calendar.dateComponents([.year, .month, .day], from: startDate)
        self.id = UUID()
        self.modeRaw = mode.rawValue
        self.startDate = calendar.startOfDay(for: startDate)
        self.startYear = civil.year ?? 1970
        self.startMonth = civil.month ?? 1
        self.startDay = civil.day ?? 1
        self.highestDayReached = 1
        self.totalDays = totalDays
        self.shareProgressWithFriends = false
        self.bodyWeightPounds = bodyWeightPounds
        self.attemptNumber = 1
    }

    /// Calendar for all day arithmetic. Pinned to Gregorian so the stored civil date always
    /// means the same thing, but using the device's *current* time zone, so "today" is
    /// whatever today is where the user actually is.
    private static var dayCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    var mode: ChallengeMode {
        get { ChallengeMode(rawValue: modeRaw) ?? .soft }
        set { modeRaw = newValue.rawValue }
    }

    /// Which day of the challenge the user is on, in their local time zone.
    ///
    /// Both ends of the comparison are midnights resolved by the same calendar and zone,
    /// so the difference is a whole number of days — which also makes this correct across
    /// a daylight-saving change, where a local day is 23 or 25 hours long.
    var currentDayNumber: Int {
        let calendar = Self.dayCalendar
        guard let start = calendar.date(from: DateComponents(year: startYear, month: startMonth, day: startDay)),
              let today = calendar.date(from: calendar.dateComponents([.year, .month, .day], from: .now)),
              let elapsed = calendar.dateComponents([.day], from: start, to: today).day
        else { return min(max(highestDayReached, 1), totalDays) }

        let fromCalendar = min(max(elapsed + 1, 1), totalDays)
        return min(max(fromCalendar, highestDayReached), totalDays)
    }

    /// Records the furthest day reached. A computed property can't persist anything, so the
    /// view calls this when it appears, when the app returns to the foreground, and when the
    /// system reports the day or time zone changing.
    func advanceDayIfNeeded() {
        let reached = currentDayNumber
        if reached > highestDayReached {
            highestDayReached = reached
        }
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
        let calendar = Self.dayCalendar
        let civil = calendar.dateComponents([.year, .month, .day], from: .now)
        startDate = calendar.startOfDay(for: .now)
        startYear = civil.year ?? startYear
        startMonth = civil.month ?? startMonth
        startDay = civil.day ?? startDay
        highestDayReached = 1
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
