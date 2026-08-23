import Foundation

/// The three tiers of the challenge.
///
/// Rules sourced from:
/// - 75 Hard: andyfrisella.com/blogs/articles/what-is-75-hard (the canonical program)
/// - 75 Soft / 75 Medium: community variants with no single owner; rules here follow the
///   most widely published consensus (Cleveland Clinic, Healthline, Marathon Handbook).
///   Because the softer tiers are not owned by anyone, users can adjust goals in Settings.
enum ChallengeMode: String, Codable, CaseIterable, Identifiable {
    case soft = "75 Soft"
    case medium = "75 Medium"
    case hard = "75 Hard"

    var id: String { rawValue }

    var tagline: String {
        switch self {
        case .soft: return "Build the habit. Miss a day, pick up where you left off."
        case .medium: return "Real structure, some grace. Hit 68 of 75 days to finish."
        case .hard: return "Zero exceptions. Miss anything and you restart at Day 1."
        }
    }

    var tasks: [TaskKind] {
        switch self {
        case .soft:
            return [
                .workout(minutes: 45, count: 1, outdoorRequired: false),
                .diet(.mindful),
                .water(.liters(3.0)),
                .reading(.pages(10), nonFictionOnly: false),
            ]
        case .medium:
            return [
                .workout(minutes: 45, count: 1, outdoorRequired: false),
                .diet(.ninetyTen),
                .water(.halfBodyWeightInOunces),
                .noAlcohol,
                .reading(.minutes(10), nonFictionOnly: false),
                .meditation(minutes: 5),
            ]
        case .hard:
            return [
                .workout(minutes: 45, count: 2, outdoorRequired: true),
                .diet(.strict),
                .water(.gallon),
                .noAlcohol,
                .reading(.pages(10), nonFictionOnly: true),
                .progressPhoto,
            ]
        }
    }

    /// 75 Soft is the only tier with a built-in weekly rest day; Medium and Hard are daily.
    var allowsWeeklyRestDay: Bool { self == .soft }

    var failurePolicy: FailurePolicy {
        switch self {
        case .soft: return .forgiving
        case .medium: return .allowedMisses(7)   // finish by completing 68 of 75 days
        case .hard: return .restartFromDayOne
        }
    }

    /// Only 75 Hard makes a progress photo a daily requirement. Soft and Medium call for a
    /// Day 1 and Day 75 photo, with anything in between optional but encouraged.
    var photoCadence: PhotoCadence {
        switch self {
        case .soft, .medium: return .milestone
        case .hard: return .daily
        }
    }

    /// Medium scales water to body weight, so onboarding has to ask for it.
    var requiresBodyWeight: Bool {
        tasks.contains { task in
            if case .water(.halfBodyWeightInOunces) = task { return true }
            return false
        }
    }

    /// Notes that don't map to a daily checkbox but that the user should see.
    var guidelines: [String] {
        switch self {
        case .soft:
            return ["Alcohol on social occasions only", "One active-recovery day per week", "Read any book — fiction counts"]
        case .medium:
            return ["Stick to your diet 90% of the time", "No alcohol for the full 75 days", "Reading or podcasts both count"]
        case .hard:
            return ["No cheat meals, no deviations", "One workout must be outdoors, in any weather", "Non-fiction only — audiobooks don't count"]
        }
    }
}

enum FailurePolicy: Codable, Hashable {
    /// 75 Hard: miss any task and the challenge resets to Day 1.
    case restartFromDayOne
    /// 75 Medium: the challenge survives up to N incomplete days.
    case allowedMisses(Int)
    /// 75 Soft: missing a day breaks the streak but never the challenge.
    case forgiving
}

enum PhotoCadence: Codable, Hashable {
    case daily
    case milestone
}

enum DietStrictness: String, Codable, Hashable {
    case mindful    // 75 Soft — eat well, no formal cheat-meal accounting
    case ninetyTen  // 75 Medium — on-plan 90% of the time
    case strict     // 75 Hard — zero cheat meals

    var label: String {
        switch self {
        case .mindful: return "Eat Well Today"
        case .ninetyTen: return "Diet (90/10)"
        case .strict: return "Diet — No Cheats"
        }
    }
}

enum WaterGoal: Codable, Hashable {
    case liters(Double)
    case gallon
    case halfBodyWeightInOunces

    /// Resolved against the user's body weight where the tier calls for it.
    func resolvedLiters(bodyWeightPounds: Double?) -> Double {
        switch self {
        case .liters(let value):
            return value
        case .gallon:
            return 3.785
        case .halfBodyWeightInOunces:
            guard let pounds = bodyWeightPounds, pounds > 0 else { return 3.0 }
            return (pounds / 2) * 0.0295735
        }
    }

    var shortLabel: String {
        switch self {
        case .liters(let value): return "\(value.formatted(.number.precision(.fractionLength(0...1))))L"
        case .gallon: return "1 gal"
        case .halfBodyWeightInOunces: return "½ body weight (oz)"
        }
    }
}

enum ReadingGoal: Codable, Hashable {
    case pages(Int)
    case minutes(Int)
}

enum TaskKind: Codable, Hashable, Identifiable {
    case workout(minutes: Int, count: Int, outdoorRequired: Bool)
    case diet(DietStrictness)
    case water(WaterGoal)
    case reading(ReadingGoal, nonFictionOnly: Bool)
    case meditation(minutes: Int)
    case progressPhoto
    case noAlcohol

    /// Stable across goal changes so completion history survives a user editing their targets.
    var id: String {
        switch self {
        case .workout: return "workout"
        case .diet: return "diet"
        case .water: return "water"
        case .reading: return "reading"
        case .meditation: return "meditation"
        case .progressPhoto: return "photo"
        case .noAlcohol: return "no-alcohol"
        }
    }

    var title: String {
        switch self {
        case .workout(let minutes, let count, let outdoor):
            if count > 1 { return "\(count) × \(minutes)-Min Workouts\(outdoor ? " (1 outdoor)" : "")" }
            return "\(minutes)-Minute Workout"
        case .diet(let strictness): return strictness.label
        case .water(let goal): return "Drink \(goal.shortLabel) of Water"
        case .reading(let goal, let nonFictionOnly):
            switch goal {
            case .pages(let pages): return "Read \(pages) Pages\(nonFictionOnly ? " (Non-Fiction)" : "")"
            case .minutes(let minutes): return "Read \(minutes) Minutes"
            }
        case .meditation(let minutes): return "Meditate \(minutes) Minutes"
        case .progressPhoto: return "Progress Photo"
        case .noAlcohol: return "No Alcohol"
        }
    }

    var systemImage: String {
        switch self {
        case .workout: return "figure.run"
        case .diet: return "fork.knife"
        case .water: return "drop.fill"
        case .reading: return "book.fill"
        case .meditation: return "brain.head.profile"
        case .progressPhoto: return "camera.fill"
        case .noAlcohol: return "wineglass"
        }
    }
}
