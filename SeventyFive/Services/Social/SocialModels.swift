import Foundation

/// A friend's progress as last fetched from CloudKit.
///
/// Everything here was written by *another person's device*, so it is treated as untrusted
/// input: `init(record:)`-style decoding clamps every number and sanitises the name before
/// it ever reaches a view.
struct FriendSnapshot: Identifiable, Codable, Equatable {
    let id: String              // the friend's Profile record name
    var displayName: String
    var isSharing: Bool
    var tier: String?
    var day: Int
    var totalDays: Int
    var streak: Int
    var todayFraction: Double
    var updatedAt: Date?

    /// True when their snapshot is from today in *their* sense — close enough to show
    /// today's ring rather than "last seen".
    var isFresh: Bool {
        guard let updatedAt else { return false }
        return Date().timeIntervalSince(updatedAt) < 20 * 3600
    }
}

/// The local user's sharing profile, cached so Friends opens instantly offline.
struct MyProfile: Codable, Equatable {
    let recordName: String
    var displayName: String
    var inviteCode: String
}

/// What the user wants to publish today. Built by the Today screen.
struct ProgressSnapshot: Equatable {
    var tier: String
    var day: Int
    var totalDays: Int
    var streak: Int
    var todayFraction: Double
}

enum Sanitize {
    static let maxNameLength = 30

    /// Trims, strips control and invisible formatting characters, collapses whitespace and
    /// caps the length. Used on our own input *and* on anything fetched from CloudKit.
    static func displayName(_ raw: String) -> String {
        let scalars = raw.unicodeScalars.filter { scalar in
            !CharacterSet.controlCharacters.contains(scalar)
                && !CharacterSet.illegalCharacters.contains(scalar)
                && scalar.properties.generalCategory != .format   // zero-width, bidi overrides
        }
        let cleaned = String(String.UnicodeScalarView(scalars))
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return String(cleaned.prefix(maxNameLength))
    }

    /// A small blocklist for display names. Names are only visible to people who already
    /// have your invite code, and every name can be blocked and reported, so this is a
    /// first line of defence rather than the whole moderation story.
    static func isAllowedName(_ name: String) -> Bool {
        let lowered = name.lowercased()
        let compact = lowered.filter { $0.isLetter }
        let blocked = ["fuck", "shit", "cunt", "nigger", "nigga", "faggot", "retard", "whore", "slut", "rape", "kys", "killyourself"]
        return !blocked.contains { compact.contains($0) }
    }

    static func int(_ value: Any?, in range: ClosedRange<Int>) -> Int {
        let raw = (value as? Int64).map(Int.init) ?? (value as? Int) ?? range.lowerBound
        return min(max(raw, range.lowerBound), range.upperBound)
    }

    static func fraction(_ value: Any?) -> Double {
        let raw = (value as? Double) ?? 0
        guard raw.isFinite else { return 0 }
        return min(max(raw, 0), 1)
    }

    /// Invite codes: 8 characters from an alphabet with no look-alikes (no 0/O, 1/I/L).
    static let codeAlphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")

    static func normalizedCode(_ raw: String) -> String? {
        let code = raw.uppercased().filter { codeAlphabet.contains($0) }
        return code.count == 8 ? code : nil
    }

    static func newInviteCode() -> String {
        var generator = SystemRandomNumberGenerator()
        return String((0..<8).map { _ in codeAlphabet.randomElement(using: &generator)! })
    }

    static func formatted(code: String) -> String {
        guard code.count == 8 else { return code }
        return "\(code.prefix(4))-\(code.suffix(4))"
    }
}
