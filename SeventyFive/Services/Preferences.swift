import Foundation

/// UserDefaults keys for app settings. Kept in one place so a typo can't split a setting.
enum PrefKey {
    static let waterUnit = "pref.waterUnit"
    static let remindersEnabled = "pref.remindersEnabled"
    static let reminderMinutes = "pref.reminderMinutes"   // minutes after midnight
    static let appLockEnabled = "pref.appLockEnabled"
    static let acceptedHealthNote = "pref.acceptedHealthNote"
}

enum SupportInfo {
    /// Shown in Settings and used for "Report". Change before release if you want a
    /// dedicated support inbox.
    static let email = "chloeinocencio.contact@gmail.com"
    /// Served by the web build (web/privacy.html). Update once the Replit deploy URL is final.
    static let privacyPolicyURL = URL(string: "https://seventyfive.replit.app/privacy.html")!
}

enum WaterUnit: String, CaseIterable, Identifiable {
    case liters, ounces

    var id: String { rawValue }

    var label: String {
        switch self {
        case .liters: return "Liters"
        case .ounces: return "Ounces"
        }
    }

    static var localeDefault: WaterUnit {
        Locale.current.measurementSystem == .us ? .ounces : .liters
    }

    static let ouncesPerLiter = 33.814

    func format(liters: Double) -> String {
        switch self {
        case .liters:
            return "\(liters.formatted(.number.precision(.fractionLength(0...2)))) L"
        case .ounces:
            return "\(Int((liters * Self.ouncesPerLiter).rounded())) oz"
        }
    }

    /// One tap on +/−: a quarter liter, or a standard 8 oz cup.
    var stepLiters: Double {
        switch self {
        case .liters: return 0.25
        case .ounces: return 8 / Self.ouncesPerLiter
        }
    }

    /// Quick-add sizes shown as chips: a glass, a bottle, a big bottle.
    var quickAdds: [(label: String, liters: Double)] {
        switch self {
        case .liters: return [("+250 ml", 0.25), ("+500 ml", 0.5), ("+1 L", 1.0)]
        case .ounces: return [("+8 oz", 8 / Self.ouncesPerLiter), ("+16 oz", 16 / Self.ouncesPerLiter), ("+32 oz", 32 / Self.ouncesPerLiter)]
        }
    }
}
