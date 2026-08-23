import Foundation

enum ChallengeMode: String, Codable, CaseIterable, Identifiable {
    case soft = "75 Soft"
    case hard = "75 Hard"

    var id: String { rawValue }

    var tagline: String {
        switch self {
        case .soft: return "Sustainable discipline. One rest day a week, one flexible meal."
        case .hard: return "Zero exceptions. Two workouts, strict diet, no alcohol."
        }
    }

    var tasks: [TaskKind] {
        switch self {
        case .soft:
            return [.workout(count: 1, outdoorRequired: false), .diet, .water(liters: 3.0), .reading(pages: 10), .progressPhoto]
        case .hard:
            return [.workout(count: 2, outdoorRequired: true), .diet, .water(liters: 3.8), .reading(pages: 10), .progressPhoto, .noAlcohol]
        }
    }

    /// 75 Soft allows one planned rest/active-recovery day per week; 75 Hard allows none.
    var allowsWeeklyRestDay: Bool { self == .soft }
}

enum TaskKind: Codable, Hashable, Identifiable {
    case workout(count: Int, outdoorRequired: Bool)
    case diet
    case water(liters: Double)
    case reading(pages: Int)
    case progressPhoto
    case noAlcohol

    var id: String {
        switch self {
        case .workout(let count, let outdoor): return "workout-\(count)-\(outdoor)"
        case .diet: return "diet"
        case .water(let liters): return "water-\(liters)"
        case .reading(let pages): return "reading-\(pages)"
        case .progressPhoto: return "photo"
        case .noAlcohol: return "no-alcohol"
        }
    }

    var title: String {
        switch self {
        case .workout(let count, let outdoor):
            if count > 1 { return "2 Workouts (1 outdoor)" }
            return outdoor ? "Outdoor Workout" : "45-Minute Workout"
        case .diet: return "Follow Your Diet"
        case .water(let liters): return "Drink \(liters.formatted(.number.precision(.fractionLength(0...1))))L Water"
        case .reading(let pages): return "Read \(pages) Pages"
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
        case .progressPhoto: return "camera.fill"
        case .noAlcohol: return "wineglass"
        }
    }
}
